{-|
Module      : Kore.Step.Simplification.Ceil
Description : Tools for Ceil pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.Ceil
    ( simplify
    , makeEvaluate
    , makeEvaluateTerm
    , simplifyEvaluated
    , Ceil (..)
    ) where

import Prelude.Kore

import Control.Error
    ( MaybeT
    , maybeT
    )
import Control.Monad.Reader
    ( MonadReader
    )
import qualified Control.Monad.Reader as Reader
import qualified Data.Functor.Foldable as Recursive

import qualified Kore.Attribute.Symbol as Attribute.Symbol
    ( isTotal
    )
import Kore.Attribute.Synthetic
    ( synthesize
    )
import qualified Kore.Builtin.AssocComm.CeilSimplifier as AssocComm
import qualified Kore.Internal.Condition as Condition
import Kore.Internal.Conditional
    ( Conditional (..)
    )
import Kore.Internal.InternalList
import Kore.Internal.InternalMap
import Kore.Internal.InternalSet
import qualified Kore.Internal.MultiAnd as MultiAnd
import qualified Kore.Internal.MultiOr as MultiOr
import Kore.Internal.OrCondition
    ( OrCondition
    )
import qualified Kore.Internal.OrCondition as OrCondition
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeCeilPredicate_
    )
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.SideCondition
    ( SideCondition
    )
import qualified Kore.Internal.SideCondition.SideCondition as SideCondition
    ( Representation
    )
import Kore.Internal.TermLike
import qualified Kore.Sort as Sort
import qualified Kore.Step.Function.Evaluator as Axiom
    ( evaluatePattern
    )
import qualified Kore.Step.Simplification.AndPredicates as And
import Kore.Step.Simplification.CeilSimplifier
import Kore.Step.Simplification.InjSimplifier
import Kore.Step.Simplification.Simplify as Simplifier
import Kore.TopBottom
import Kore.Unparser
    ( unparseToString
    )

{-| Simplify a 'Ceil' of 'OrPattern'.

A ceil(or) is equal to or(ceil). We also take into account that
* ceil(top) = top
* ceil(bottom) = bottom
* ceil leaves predicates and substitutions unchanged
* ceil transforms terms into predicates
-}
simplify
    :: (InternalVariable variable, MonadSimplify simplifier)
    => SideCondition variable
    -> Ceil Sort (OrPattern variable)
    -> simplifier (OrPattern variable)
simplify
    sideCondition
    Ceil { ceilChild = child }
  =
    simplifyEvaluated sideCondition child

{-| 'simplifyEvaluated' evaluates a ceil given its child, see 'simplify'
for details.
-}
{- TODO (virgil): Preserve pattern sorts under simplification.

One way to preserve the required sort annotations is to make 'simplifyEvaluated'
take an argument of type

> CofreeF (Ceil Sort) (Attribute.Pattern variable) (OrPattern variable)

instead of an 'OrPattern' argument. The type of 'makeEvaluate' may
be changed analogously. The 'Attribute.Pattern' annotation will eventually cache
information besides the pattern sort, which will make it even more useful to
carry around.

-}
simplifyEvaluated
    :: InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> OrPattern variable
    -> simplifier (OrPattern variable)
simplifyEvaluated sideCondition child =
    OrPattern.flatten
    <$> OrPattern.traverse (makeEvaluate sideCondition) child

{-| Evaluates a ceil given its child as an Pattern, see 'simplify'
for details.
-}
makeEvaluate
    :: InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> Pattern variable
    -> simplifier (OrPattern variable)
makeEvaluate sideCondition child
  | Pattern.isTop    child = return OrPattern.top
  | Pattern.isBottom child = return OrPattern.bottom
  | otherwise              = makeEvaluateNonBoolCeil sideCondition child

makeEvaluateNonBoolCeil
    :: InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> Pattern variable
    -> simplifier (OrPattern variable)
makeEvaluateNonBoolCeil sideCondition patt@Conditional {term}
  | isTop term =
    return $ OrPattern.fromPattern
        patt {term = mkTop_} -- erase the term's sort.
  | otherwise = do
    termCeil <- makeEvaluateTerm sideCondition term
    result <-
        And.simplifyEvaluatedMultiPredicate
            sideCondition
            (MultiAnd.make
                [ MultiOr.make [Condition.eraseConditionalTerm patt]
                , termCeil
                ]
            )
    return (OrPattern.map Pattern.fromCondition_ result)

-- TODO: Ceil(function) should be an and of all the function's conditions, both
-- implicit and explicit.
{-| Evaluates the ceil of a TermLike, see 'simplify' for details.
-}
makeEvaluateTerm
    :: forall variable simplifier
    .  InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> TermLike variable
    -> simplifier (OrCondition variable)
makeEvaluateTerm sideCondition ceilChild =
    runCeilSimplifierWith
        ceilSimplifier
        sideCondition
        Ceil
            { ceilResultSort = Sort.predicateSort
            , ceilOperandSort = termLikeSort ceilChild
            , ceilChild
            }
    & maybeT (makeSimplifiedCeil sideCondition Nothing ceilChild) return
  where
    ceilSimplifier =
        mconcat
        [ newPredicateCeilSimplifier
        , newDefinedCeilSimplifier
        , newApplicationCeilSimplifier
        , newBuiltinCeilSimplifier
        , newInjCeilSimplifier
        , newAxiomCeilSimplifier
        ]

newPredicateCeilSimplifier
    :: Monad simplifier
    => InternalVariable variable
    => CeilSimplifier simplifier (TermLike variable) (OrCondition variable)
newPredicateCeilSimplifier = CeilSimplifier $ \input ->
    case Predicate.makePredicate (ceilChild input) of
        Left _ -> empty
        Right predicate -> return (OrCondition.fromPredicate predicate)

newDefinedCeilSimplifier
    :: Monad simplifier
    => InternalVariable variable
    => CeilSimplifier simplifier (TermLike variable) (OrCondition variable)
newDefinedCeilSimplifier = CeilSimplifier $ \input ->
    if isDefinedPattern (ceilChild input)
        then return OrCondition.top
        else empty

newApplicationCeilSimplifier
    :: MonadReader (SideCondition variable) simplifier
    => MonadSimplify simplifier
    => InternalVariable variable
    => CeilSimplifier simplifier (TermLike variable) (OrCondition variable)
newApplicationCeilSimplifier = CeilSimplifier $ \input ->
    case ceilChild input of
        App_ patternHead children
          | let headAttributes = symbolAttributes patternHead
          , Attribute.Symbol.isTotal headAttributes -> do
            sideCondition <- Reader.ask
            let mkChildCeil =
                    makeEvaluateTermCeil
                        sideCondition
                        Sort.predicateSort
            simplifiedChildren <- mapM mkChildCeil children
            let ceils = simplifiedChildren
            And.simplifyEvaluatedMultiPredicate
                sideCondition
                (MultiAnd.make ceils)
        _ -> empty

newInjCeilSimplifier
    :: MonadReader (SideCondition variable) simplifier
    => MonadSimplify simplifier
    => InternalVariable variable
    => CeilSimplifier simplifier (TermLike variable) (OrCondition variable)
newInjCeilSimplifier = CeilSimplifier $ \input ->
    case ceilChild input of
        Inj_ inj -> do
            InjSimplifier { evaluateCeilInj } <- askInjSimplifier
            sideCondition <- Reader.ask
            input { ceilChild = inj }
                & evaluateCeilInj
                & ceilChild
                & makeEvaluateTermCeil sideCondition Sort.predicateSort
        _ -> empty

newBuiltinCeilSimplifier
    :: MonadReader (SideCondition variable) simplifier
    => MonadSimplify simplifier
    => InternalVariable variable
    => CeilSimplifier simplifier (TermLike variable) (OrCondition variable)
newBuiltinCeilSimplifier = CeilSimplifier $ \input ->
    case ceilChild input of
        InternalList_ internal -> do
            sideCondition <- Reader.ask
            makeEvaluateInternalList sideCondition internal
        InternalMap_ internalMap -> do
            sideCondition <- Reader.ask
            makeEvaluateInternalMap sideCondition internalMap
        InternalSet_ internalSet -> do
            sideCondition <- Reader.ask
            makeEvaluateInternalSet sideCondition internalSet
        _ -> empty

newAxiomCeilSimplifier
    :: MonadReader (SideCondition variable) simplifier
    => MonadSimplify simplifier
    => InternalVariable variable
    => CeilSimplifier simplifier (TermLike variable) (OrCondition variable)
newAxiomCeilSimplifier = CeilSimplifier $ \input -> do
    sideCondition <- Reader.ask
    evaluation <- Axiom.evaluatePattern
        sideCondition
        Condition.top
        (synthesize $ CeilF input)
        (const empty)
    return (OrPattern.map toCondition evaluation)
  where
    toCondition Conditional {term = Top_ _, predicate, substitution} =
        Conditional {term = (), predicate, substitution}
    toCondition patt =
        error
            (  "Ceil simplification is expected to result ai a predicate, but"
            ++ " got (" ++ show patt ++ ")."
            ++ " The most likely cases are: evaluating predicate symbols, "
            ++ " and predicate symbols are currently unrecognized as such, "
            ++ "and programming errors."
            )

makeEvaluateInternalMap
    :: forall variable simplifier
    .  InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> InternalMap (TermLike Concrete) (TermLike variable)
    -> MaybeT simplifier (OrCondition variable)
makeEvaluateInternalMap sideCondition internalMap =
    runCeilSimplifierWith
        AssocComm.newMapCeilSimplifier
        sideCondition
        Ceil
            { ceilResultSort = Sort.predicateSort
            , ceilOperandSort = builtinAcSort
            , ceilChild = internalMap
            }
  where
    InternalAc { builtinAcSort } = internalMap

{-| Evaluates the ceil of a domain value.
-}
makeEvaluateInternalSet
    :: forall variable simplifier
    .  InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> InternalSet (TermLike Concrete) (TermLike variable)
    -> MaybeT simplifier (OrCondition variable)
makeEvaluateInternalSet sideCondition internalSet =
    runCeilSimplifierWith
        AssocComm.newSetCeilSimplifier
        sideCondition
        Ceil
            { ceilResultSort = Sort.predicateSort
            , ceilOperandSort = builtinAcSort
            , ceilChild = internalSet
            }
  where
    InternalAc { builtinAcSort } = internalSet

makeEvaluateInternalList
    :: forall variable simplifier
    .  InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> InternalList (TermLike variable)
    -> simplifier (OrCondition variable)
makeEvaluateInternalList sideCondition internal = do
    children <- mapM (makeEvaluateTerm sideCondition) (toList internal)
    let
        ceils :: [OrCondition variable]
        ceils = children
    And.simplifyEvaluatedMultiPredicate sideCondition (MultiAnd.make ceils)

{-| This handles the case when we can't simplify a term's ceil.

It returns the ceil of that term.

When the term's ceil implies the ceils of its subterms, this also @and@s
the subterms' simplified ceils to the result. This is needed because the
SMT solver can't infer a subterm's ceil from a term's ceil, so we
have to provide that information.

As an example, if we call @makeSimplifiedCeil@ for @f(g(x))@, and we don't
know how to simplify @ceil(g(x))@, the return value will be
@and(ceil(f(g(x))), ceil(g(x)))@.

-}
makeSimplifiedCeil
    :: (InternalVariable variable, MonadSimplify simplifier)
    => SideCondition variable
    -> Maybe SideCondition.Representation
    -> TermLike variable
    -> simplifier (OrCondition variable)
makeSimplifiedCeil
    sideCondition
    maybeCurrentCondition
    termLike@(Recursive.project -> _ :< termLikeF)
  = do
    childCeils <- if needsChildCeils
        then mapM (makeEvaluateTerm sideCondition) (toList termLikeF)
        else return []
    And.simplifyEvaluatedMultiPredicate
        sideCondition
        (MultiAnd.make (unsimplified : childCeils))
  where
    needsChildCeils = case termLikeF of
        ApplyAliasF _ -> False
        EvaluatedF  _ -> False
        DefinedF  _ -> False
        EndiannessF _ -> True
        SignednessF _ -> True
        AndF _ -> True
        ApplySymbolF _ -> True
        InjF _ -> True
        CeilF _ -> unexpectedError
        EqualsF _ -> unexpectedError
        ExistsF _ -> False
        IffF _ -> False
        ImpliesF _ -> False
        InF _ -> False
        NotF _ -> False
        BottomF _ -> unexpectedError
        DomainValueF _ -> True
        FloorF _ -> False
        ForallF _ -> False
        InhabitantF _ -> False
        MuF _ -> False
        NuF _ -> False
        NextF _ -> True
        OrF _ -> False
        RewritesF _ -> False
        TopF _ -> unexpectedError
        StringLiteralF _ -> unexpectedError
        InternalBoolF _ -> unexpectedError
        InternalBytesF _ -> unexpectedError
        InternalIntF _ -> unexpectedError
        InternalListF _ -> True
        InternalMapF _ -> True
        InternalSetF _ -> True
        InternalStringF _ -> unexpectedError
        VariableF _ -> False

    unsimplified =
        OrCondition.fromPredicate
        . Predicate.markSimplifiedMaybeConditional maybeCurrentCondition
        . makeCeilPredicate_
        $ termLike

    unexpectedError =
        error ("Unexpected term type: " ++ unparseToString termLike)
