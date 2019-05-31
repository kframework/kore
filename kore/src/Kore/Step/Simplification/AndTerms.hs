{-|
Module      : Kore.Step.Simplification.AndTerms
Description : Unification and "and" simplification for terms.
Copyright   : (c) Runtime Verification, 2018
License     : UIUC/NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.AndTerms
    ( simplifySortInjections
    , termAnd
    , termEquals
    , termUnification
    , SortInjectionMatch (..)
    , SortInjectionSimplification (..)
    , TermSimplifier
    , TermTransformationOld
    , cannotUnifyDistinctDomainValues
    ) where

import           Control.Applicative
                 ( Alternative (..) )
import           Control.Error
                 ( MaybeT (..), fromMaybe, mapMaybeT )
import qualified Control.Error as Error
import           Control.Exception
                 ( assert )
import qualified Control.Monad as Monad
import qualified Control.Monad.Trans as Monad.Trans
import qualified Data.Foldable as Foldable
import qualified Data.Functor.Foldable as Recursive
import           Data.Reflection
                 ( give )
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Prettyprint.Doc as Pretty
import           Prelude hiding
                 ( concat )

import           Kore.Attribute.Symbol
                 ( SortInjection (..), StepperAttributes )
import qualified Kore.Attribute.Symbol as Attribute
import qualified Kore.Builtin.List as Builtin.List
import qualified Kore.Builtin.Map as Builtin.Map
import qualified Kore.Builtin.Set as Builtin.Set
import qualified Kore.Domain.Builtin as Domain
import           Kore.IndexedModule.MetadataTools
import qualified Kore.IndexedModule.MetadataTools as MetadataTools
                 ( MetadataTools (..) )
import qualified Kore.Internal.MultiOr as MultiOr
import           Kore.Internal.OrPredicate
                 ( OrPredicate )
import qualified Kore.Internal.OrPredicate as OrPredicate
import           Kore.Internal.Pattern
                 ( Conditional (..), Pattern )
import qualified Kore.Internal.Pattern as Pattern
import qualified Kore.Internal.Predicate as Predicate
import           Kore.Internal.TermLike
import qualified Kore.Logger as Logger
import           Kore.Predicate.Predicate
                 ( pattern PredicateTrue, makeEqualsPredicate,
                 makeNotPredicate, makeTruePredicate )
import           Kore.Step.PatternAttributes
                 ( isConstructorLikeTop )
import           Kore.Step.RecursiveAttributes
                 ( isFunctionPattern )
import           Kore.Step.Simplification.Data as Simplifier
import qualified Kore.Step.Simplification.Data as SimplificationType
                 ( SimplificationType (..) )
import qualified Kore.Step.Simplification.Data as BranchT
                 ( gather, scatter )
import           Kore.Step.Substitution
                 ( PredicateMerger,
                 createLiftedPredicatesAndSubstitutionsMerger,
                 createPredicatesAndSubstitutionsMergerExcept )
import           Kore.TopBottom
import           Kore.Unification.Error
                 ( unsupportedPatterns )
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unification.Unify
                 ( MonadUnify, Unifier )
import qualified Kore.Unification.Unify as Monad.Unify
import           Kore.Unparser
import           Kore.Variables.Fresh

import {-# SOURCE #-} qualified Kore.Step.Simplification.Ceil as Ceil
                 ( makeEvaluateTerm )

data SimplificationTarget = AndT | EqualsT | BothT

type TermSimplifier variable m =
    TermLike variable -> TermLike variable -> m (Pattern variable)

{- | Simplify an equality relation of two patterns.

@termEquals@ assumes the result will be part of a predicate with a special
condition for testing @⊥ = ⊥@ equality.

The comment for 'Kore.Step.Simplification.And.simplify' describes all
the special cases handled by this.

See also: 'termAnd'

 -}
termEquals
    ::  ( FreshVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> TermLike variable
    -> TermLike variable
    -> MaybeT Simplifier (OrPredicate variable)
termEquals
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    first
    second
  = MaybeT $ do
    maybeResults <-
        BranchT.gather $ runMaybeT $ termEqualsAnd
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier
            first
            second
    case sequence maybeResults of
        Nothing -> return Nothing
        Just results -> return $ Just $
            MultiOr.make (map Predicate.eraseConditionalTerm results)

termEqualsAnd
    :: forall variable .
        ( FreshVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> TermLike variable
    -> TermLike variable
    -> MaybeT (BranchT Simplifier) (Pattern variable)
termEqualsAnd
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    p1
    p2
  =
    MaybeT $ do
        eitherMaybeResult <-
            Monad.Trans.lift . Monad.Unify.runUnifier
            . runMaybeT
            $ maybeTermEquals
                substitutionSimplifier
                simplifier
                axiomIdToSimplifier
                (createPredicatesAndSubstitutionsMergerExcept
                    substitutionSimplifier
                    simplifier
                    axiomIdToSimplifier
                )
                termEqualsAndWorker
                p1
                p2
        case eitherMaybeResult of
            Left _ -> return Nothing
            Right results -> BranchT.scatter results
  where
    termEqualsAndWorker
        :: MonadUnify unifier
        => TermLike variable
        -> TermLike variable
        -> unifier (Pattern variable)
    termEqualsAndWorker first second = Monad.Unify.liftBranchedSimplifier $ do
        eitherMaybeTermEqualsAndChild <-
            Monad.Trans.lift $ Monad.Unify.runUnifier $ runMaybeT
            $ maybeTermEquals
                substitutionSimplifier
                simplifier
                axiomIdToSimplifier
                (createPredicatesAndSubstitutionsMergerExcept
                    substitutionSimplifier
                    simplifier
                    axiomIdToSimplifier
                )
                termEqualsAndWorker
                first
                second
        case eitherMaybeTermEqualsAndChild of
            Left _ -> return equalsPredicate
            Right maybeResults ->
                case sequence maybeResults of
                    Nothing -> return equalsPredicate
                    Just results -> BranchT.scatter results
      where
        equalsPredicate =
            Conditional
                { term = mkTop_
                , predicate = makeEqualsPredicate first second
                , substitution = mempty
                }

maybeTermEquals
    ::  ( FreshVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        , MonadUnify unifier
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> PredicateMerger variable unifier
    -> TermSimplifier variable unifier
    -- ^ Used to simplify subterm "and".
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
maybeTermEquals = maybeTransformTerm equalsFunctions

{- | Unify two terms without discarding the terms.

We want to keep the terms because substitution relies on the result not being
@\\bottom@.

Unlike 'termAnd', @termUnification@ does not make an @\\and@ term when a
particular case is not implemented; otherwise, the two are the same.

The comment for 'Kore.Step.Simplification.And.simplify' describes all
the special cases handled by this.

-}
-- NOTE (hs-boot): Please update the AndTerms.hs-boot file when changing the
-- signature.
termUnification
    ::  forall variable unifier
    .   ( FreshVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        , MonadUnify unifier
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> TermLike variable
    -> TermLike variable
    -> unifier (Pattern variable)
termUnification substitutionSimplifier simplifier axiomIdToSimplifier =
    termUnificationWorker
  where
    termUnificationWorker
        :: TermLike variable
        -> TermLike variable
        -> unifier (Pattern variable)
    termUnificationWorker pat1 pat2 = do
        let
            maybeTermUnification :: MaybeT unifier (Pattern variable)
            maybeTermUnification =
                maybeTermAnd
                    substitutionSimplifier
                    simplifier
                    axiomIdToSimplifier
                    (createPredicatesAndSubstitutionsMergerExcept
                        substitutionSimplifier
                        simplifier
                        axiomIdToSimplifier
                    )
                    termUnificationWorker
                    pat1
                    pat2
            unsupportedPatternsError =
                Monad.Unify.throwUnificationError
                    (unsupportedPatterns
                        "Unknown unification case."
                        pat1
                        pat2
                    )
        Error.maybeT unsupportedPatternsError pure $ maybeTermUnification

{- | Simplify the conjunction (@\\and@) of two terms.

The comment for 'Kore.Step.Simplification.And.simplify' describes all the
special cases
handled by this.

See also: 'termUnification'

-}
-- NOTE (hs-boot): Please update AndTerms.hs-boot file when changing the
-- signature.
termAnd
    :: forall variable .
        ( FreshVariable variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> TermLike variable
    -> TermLike variable
    -> BranchT Simplifier (Pattern variable)
termAnd substitutionSimplifier simplifier axiomIdToSimplifier p1 p2 = do
    eitherResult <- Monad.Trans.lift $ Monad.Unify.runUnifier $
        termAndWorker p1 p2
    case eitherResult of
        Left _        -> return $ Pattern.fromTermLike (mkAnd p1 p2)
        Right results -> BranchT.scatter results
  where
    termAndWorker
        :: TermLike variable
        -> TermLike variable
        -> Unifier (Pattern variable)
    termAndWorker first second = do
        let maybeTermAnd' =
                maybeTermAnd
                    substitutionSimplifier
                    simplifier
                    axiomIdToSimplifier
                    (createLiftedPredicatesAndSubstitutionsMerger
                        substitutionSimplifier
                        simplifier
                        axiomIdToSimplifier
                    )
                    termAndWorker
                    first
                    second
        patt <- runMaybeT maybeTermAnd'
        return $ fromMaybe andPattern patt
      where
        andPattern = Pattern.fromTermLike (mkAnd first second)

maybeTermAnd
    ::  ( FreshVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        , MonadUnify unifier
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> PredicateMerger variable unifier
    -> TermSimplifier variable unifier
    -- ^ Used to simplify subterm "and".
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
maybeTermAnd = maybeTransformTerm andFunctions

andFunctions
    ::  forall variable unifier
    .   ( FreshVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        , MonadUnify unifier
        )
    => [TermTransformationOld variable unifier]
andFunctions =
    map (forAnd . snd) (filter appliesToAnd andEqualsFunctions)
  where
    appliesToAnd :: (SimplificationTarget, a) -> Bool
    appliesToAnd (AndT, _) = True
    appliesToAnd (EqualsT, _) = False
    appliesToAnd (BothT, _) = True

    forAnd
        :: TermTransformation variable unifier
        -> TermTransformationOld variable unifier
    forAnd f = f SimplificationType.And

equalsFunctions
    ::  forall variable unifier
    .   ( FreshVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        , MonadUnify unifier
        )
    => [TermTransformationOld variable unifier]
equalsFunctions =
    map (forEquals . snd) (filter appliesToEquals andEqualsFunctions)
  where
    appliesToEquals :: (SimplificationTarget, a) -> Bool
    appliesToEquals (AndT, _) = False
    appliesToEquals (EqualsT, _) = True
    appliesToEquals (BothT, _) = True

    forEquals
        :: TermTransformation variable unifier
        -> TermTransformationOld variable unifier
    forEquals f = f SimplificationType.Equals

andEqualsFunctions
    ::  forall variable unifier
    .   ( Eq variable
        , FreshVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        , MonadUnify unifier
        )
    => [(SimplificationTarget, TermTransformation variable unifier)]
andEqualsFunctions = fmap mapEqualsFunctions
    [ (AndT,    liftE0 boolAnd, "boolAnd")
    , (BothT,   liftET equalAndEquals, "equalAndEquals")
    , (EqualsT, lift0  bottomTermEquals, "bottomTermEquals")
    , (EqualsT, lift0  termBottomEquals, "termBottomEquals")
    , (BothT,   liftTS variableFunctionAndEquals, "variableFunctionAndEquals")
    , (BothT,   liftTS functionVariableAndEquals, "functionVariableAndEquals")
    , (BothT,   addT   equalInjectiveHeadsAndEquals, "equalInjectiveHeadsAndEquals")
    , (BothT,   addS   sortInjectionAndEqualsAssumesDifferentHeads, "sortInjectionAndEqualsAssumesDifferentHeads")
    , (BothT,   liftE0 constructorSortInjectionAndEquals, "constructorSortInjectionAndEquals")
    , (BothT,   liftE0 constructorAndEqualsAssumesDifferentHeads, "constructorAndEqualsAssumesDifferentHeads")
    , (BothT,   liftB1 Builtin.Map.unifyEquals, "Builtin.Map.unifyEquals")
    , (BothT,   liftB1 Builtin.Set.unifyEquals, "Builtin.Set.unifyEquals")
    , (BothT,   liftB  Builtin.List.unifyEquals, "Builtin.List.unifyEquals")
    , (BothT,   liftE  domainValueAndConstructorErrors, "domainValueAndConstructorErrors")
    , (BothT,   liftE0 domainValueAndEqualsAssumesDifferent, "domainValueAndEqualsAssumesDifferent")
    , (BothT,   liftE0 stringLiteralAndEqualsAssumesDifferent, "stringLiteralAndEqualsAssumesDifferent")
    , (BothT,   liftE0 charLiteralAndEqualsAssumesDifferent, "charLiteralAndEqualsAssumesDifferent")
    , (AndT,    lift   functionAnd, "functionAnd")
    ]
  where
    mapEqualsFunctions (target, termTransform, name) =
        (target, logTT name termTransform)

    logTT
        :: String
        -> TermTransformation variable unifier
        -> TermTransformation variable unifier
    logTT fnName termTransformation sType tools ps tls bs pm ts t1 t2 =
        mapMaybeT (\getResult -> do
            mresult <- getResult
            case mresult of
                Nothing -> do
                    Monad.Unify.liftSimplifier
                        . Logger.withLogScope (Logger.Scope "AndTerms")
                        . Logger.logDebug
                        . Text.pack
                        . show
                        $ Pretty.hsep
                                [ "Evaluator"
                                , Pretty.pretty fnName
                                , "does not apply."
                                ]
                    return mresult
                Just result -> do
                    Monad.Unify.liftSimplifier
                        . Logger.withLogScope (Logger.Scope "AndTerms")
                        . Logger.logInfo
                        . Text.pack
                        . show
                        $ Pretty.vsep
                            [ Pretty.hsep
                                [ "Evaluator"
                                , Pretty.pretty fnName
                                ]
                            , Pretty.indent 4 $ Pretty.vsep
                                [ "First:"
                                , Pretty.indent 4 $ unparse t1
                                , "Second:"
                                , Pretty.indent 4 $ unparse t2
                                , "Result:"
                                , Pretty.indent 4 $ unparse result
                                ]
                            ]
                    return mresult
            )
            $ termTransformation sType tools ps tls bs pm ts t1 t2

    liftB
        f
        simplificationType
        tools
        substitutionSimplifier
        _simplifier
        _axiomIdToSimplifier
        _substitutionMerger
      =
        f
            simplificationType
            tools
            substitutionSimplifier
    liftB1
        f
        simplificationType
        tools
        substitutionSimplifier
        simplifier
        axiomIdToSimplifier
        _substitutionMerger
      =
        f
            simplificationType
            tools
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier

    lift = pure . transformerLiftOld
    liftE = lift . toExpanded
    liftE0
        f
        _simplificationType
        _tools
        _substitutionSimplifier
        _simplifier
        _axiomIdToSimplifier
        _substitutionMerger
        _termSimplifier
        first
        second
      = Pattern.fromTermLike <$> f first second
    liftET = liftE . addToolsArg
    addS
        f
        _simplificationType
        _tools
        _substitutionSimplifier
        _simplifier
        _axiomIdToSimplifier
        _substitutionMerger
      = f
    addT
        ::  (  PredicateMerger variable unifier
            -> TermSimplifier variable unifier
            -> TermLike variable
            -> TermLike variable
            -> MaybeT unifier (Pattern variable)
            )
        -> TermTransformation variable unifier
    addT
        f
        _simplificationType
        _tools
        _substitutionSimplifier
        _simplifier
        _axiomIdToSimplifier
      =
        f
    lift0
        f
        _simplificationType
        _tools
        substitutionSimplifier
        simplifier
        axiomIdToSimplifier
        _substitutionMerger
        _termSimplifier
        p1
        p2
      = f substitutionSimplifier simplifier axiomIdToSimplifier p1 p2
    liftTS
        f
        simplificationType
        _tools
        substitutionSimplifier
        simplifier
        axiomIdToSimplifier
        substitutionMerger
        _termSimplifier
      =
        f
            simplificationType
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier
            substitutionMerger


{- | Construct the conjunction or unification of two terms.

Each @TermTransformationOld@ should represent one unification case and each
unification case should be handled by only one @TermTransformationOld@. If the
pattern heads do not match the case under consideration, call 'empty' to allow
another case to handle the patterns. If the pattern heads do match the
unification case, then use 'Control.Monad.Trans.lift' to wrap the implementation
of that case.

All the @TermTransformationOld@s and similar functions defined in this module
call 'empty' unless given patterns matching their unification case.

 -}
type TermTransformation variable unifier =
       SimplificationType
    -> SmtMetadataTools StepperAttributes
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> PredicateMerger variable unifier
    -> TermSimplifier variable unifier
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)

type TermTransformationOld variable unifier =
       SmtMetadataTools StepperAttributes
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> PredicateMerger variable unifier
    -> TermSimplifier variable unifier
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)

maybeTransformTerm
    ::  ( FreshVariable variable
        , Ord variable
        , Ord variable
        , Ord variable
        , Show variable
        , SortedVariable variable
        , MonadUnify unifier
        )
    => [TermTransformationOld variable unifier]
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> PredicateMerger variable unifier
    -> TermSimplifier variable unifier
    -- ^ Used to simplify subterm pairs.
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
maybeTransformTerm
    topTransformers
    mergeException
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    childTransformers
    first
    second
  = do
    tools <- Simplifier.askMetadataTools
    foldr
        (<|>)
        empty
        (map
            (\f ->
                 f
                    tools
                    mergeException
                    substitutionSimplifier
                    simplifier
                    axiomIdToSimplifier
                    childTransformers
                    first
                    second
            )
            topTransformers
        )

addToolsArg
    ::  (  TermLike variable
        -> TermLike variable
        -> Maybe (TermLike variable)
        )
    ->  (  SmtMetadataTools StepperAttributes
        -> TermLike variable
        -> TermLike variable
        -> Maybe (TermLike variable)
        )
addToolsArg = pure

toExpanded
    ::  ( SortedVariable variable
        , Show variable
        , Ord variable
        )
    =>  (  SmtMetadataTools StepperAttributes
        -> TermLike variable
        -> TermLike variable
        -> Maybe (TermLike variable)
        )
    ->  (  SmtMetadataTools StepperAttributes
        -> TermLike variable
        -> TermLike variable
        -> Maybe (Pattern variable)
        )
toExpanded transformer tools first second =
    toExpanded0 <$> transformer tools first second
  where
    toExpanded0 term
      | isBottom term = Pattern.bottom
      | otherwise     = Pattern.fromTermLike term

transformerLiftOld
    :: Monad unifier
    =>  (  SmtMetadataTools StepperAttributes
        -> TermLike variable
        -> TermLike variable
        -> Maybe (Pattern variable)
        )
    -> TermTransformationOld variable unifier
transformerLiftOld
    transformation
    tools
    _substitutionSimplifier
    _simplifier
    _axiomIdToSimplifier
    _substitutionMerger
    _childSimplifier
    first
    second
  = liftPattern (transformation tools first second)

liftPattern
    :: Monad m
    => Maybe (Pattern variable)
    -> MaybeT m (Pattern variable)
liftPattern = MaybeT . return

-- | Simplify the conjunction of terms where one is a predicate.
boolAnd
    :: MonadUnify unifier
    => SortedVariable variable
    => Unparse variable
    => TermLike variable
    -> TermLike variable
    -> MaybeT unifier (TermLike variable)
boolAnd first second
  | isBottom first  = do
      Monad.Trans.lift $ Monad.Unify.explainBottom
          "Cannot unify bottom."
          first
          second
      return first
  | isTop first     = return second
  | isBottom second = do
      Monad.Trans.lift $ Monad.Unify.explainBottom
          "Cannot unify bottom."
          first
          second
      return second
  | isTop second    = return first
  | otherwise       = empty

-- | Unify two identical ('==') patterns.
equalAndEquals
    :: Eq variable
    => TermLike variable
    -> TermLike variable
    -> Maybe (TermLike variable)
equalAndEquals first second
  | first == second =
    return first
equalAndEquals _ _ = empty

-- | Unify two patterns where the first is @\\bottom@.
bottomTermEquals
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        , MonadUnify unifier
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from symbol IDs to defined functions
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
bottomTermEquals
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    first@(Bottom_ _)
    second
  = Monad.Trans.lift $ do -- MonadUnify
    tools <- Simplifier.askMetadataTools
    secondCeil <-
        Monad.Unify.liftSimplifier $ Ceil.makeEvaluateTerm
            tools
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier
            second

    case MultiOr.extractPatterns secondCeil of
        [] -> return Pattern.top
        [ Conditional { predicate = PredicateTrue, substitution } ]
          | substitution == mempty -> do
            Monad.Unify.explainBottom
                "Cannot unify bottom with non-bottom pattern."
                first
                second
            Monad.Unify.scatter []
        _ ->
            return  Conditional
                { term = mkTop_
                , predicate =
                    makeNotPredicate
                    $ OrPredicate.toPredicate
                    $ Predicate.toPredicate <$> secondCeil
                , substitution = mempty
                }
bottomTermEquals _ _ _ _ _ = empty

{- | Unify two patterns where the second is @\\bottom@.

See also: 'bottomTermEquals'

 -}
termBottomEquals
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        , MonadUnify unifier
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from symbol IDs to defined functions
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
termBottomEquals
    substitutionSimplifier simplifier axiomIdToSimplifier first second
  =
    bottomTermEquals
        substitutionSimplifier simplifier axiomIdToSimplifier second first

{- | Unify a variable with a function pattern.

See also: 'isFunctionPattern'

 -}
variableFunctionAndEquals
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        , MonadUnify unifier
        )
    => SimplificationType
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from symbol IDs to defined functions
    -> PredicateMerger variable unifier
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
variableFunctionAndEquals
    SimplificationType.And
    _substitutionSimplifier
    _simplifier
    _axiomIdToSimplifier
    _substitutionMerger
    first@(Var_ v1)
    second@(Var_ v2)
  =
    return Conditional
        { term = if v2 > v1 then second else first
        , predicate = makeTruePredicate
        , substitution =
            Substitution.wrap
                [ if v2 > v1 then (v1, second) else (v2, first) ]
        }
variableFunctionAndEquals
    simplificationType
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    _
    first@(Var_ v)
    second
  = Monad.Trans.lift $ do
    tools <- Simplifier.askMetadataTools
    Monad.guard (isFunctionPattern tools second)
    predicate <-
        case simplificationType of -- Simplifier
            SimplificationType.And ->
                -- Ceil predicate not needed since 'second' being bottom
                -- will make the entire term bottom. However, one must
                -- be careful to not just drop the term.
                return Predicate.top
            SimplificationType.Equals -> do
                resultOr <- Monad.Unify.liftSimplifier
                    $ Ceil.makeEvaluateTerm
                        tools
                        substitutionSimplifier
                        simplifier
                        axiomIdToSimplifier
                        second
                case MultiOr.extractPatterns resultOr of
                    [] -> do
                        Monad.Unify.explainBottom
                           (Pretty.hsep
                               [ "Unification of variable and bottom"
                               , "when attempting to simplify equals."
                               ]
                           )
                           first
                           second
                        Monad.Unify.scatter []
                    resultPredicates -> Monad.Unify.scatter resultPredicates
    let result = predicate <> Predicate.fromSingleSubstitution (v, second)
    return (Pattern.withCondition second result)
variableFunctionAndEquals _ _ _ _ _ _ _ = empty

{- | Unify a function pattern with a variable.

See also: 'variableFunctionAndEquals'

 -}
functionVariableAndEquals
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        , MonadUnify unifier
        )
    => SimplificationType
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from symbol IDs to defined functions
    -> PredicateMerger variable unifier
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
functionVariableAndEquals
    simplificationType
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    substitutionMerger
    first
    second
  =
    variableFunctionAndEquals
        simplificationType
        substitutionSimplifier
        simplifier
        axiomIdToSimplifier
        substitutionMerger
        second
        first

{- | Unify two application patterns with equal, injective heads.

This includes constructors and sort injections.

See also: 'Attribute.isInjective', 'Attribute.isSortInjection',
'Attribute.isConstructor'

 -}
equalInjectiveHeadsAndEquals
    ::  ( FreshVariable variable
        , Show variable
        , Unparse variable
        , SortedVariable variable
        , MonadUnify unifier
        )
    => PredicateMerger variable unifier
    -> TermSimplifier variable unifier
    -- ^ Used to simplify subterm "and".
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
equalInjectiveHeadsAndEquals
    _
    termMerger
    firstPattern@(App_ firstHead firstChildren)
    (App_ secondHead secondChildren)
  | firstHead == secondHead = do
    tools <- Simplifier.askMetadataTools
    let
        isFirstInjective = give tools Attribute.isInjective_ firstHead
        isSecondInjective = give tools Attribute.isInjective_ secondHead
    Monad.guard isFirstInjective
    Monad.guard isSecondInjective
    Monad.Trans.lift $ do
        children <- Monad.zipWithM termMerger firstChildren secondChildren
        let merged = Foldable.foldMap Pattern.withoutTerm children
            term =
                mkApp
                    (termLikeSort firstPattern)
                    firstHead
                    (Pattern.term <$> children)
        return (Pattern.withCondition term merged)
equalInjectiveHeadsAndEquals _ _ _ _ = Error.nothing

{- | Simplify the conjunction of two sort injections.

Assumes that the two heads were already tested for equality and were found
to be different.

This simplifies cases where there is a subsort relation between the injected
sorts of the conjoined patterns, such as,

@
    \inj{src1, dst}(a) ∧ \inj{src2, dst}(b)
    ===
    \inj{src2, dst}(\inj{src1, src2}(a) ∧ b)
@

when @src1@ is a subsort of @src2@.

 -}
sortInjectionAndEqualsAssumesDifferentHeads
    ::  forall variable unifier
    .   ( Ord variable
        , SortedVariable variable
        , Unparse variable
        , MonadUnify unifier )
    => TermSimplifier variable unifier
    -> TermLike variable
    -> TermLike variable
    -> MaybeT unifier (Pattern variable)
sortInjectionAndEqualsAssumesDifferentHeads
    termMerger
    first
    second
  = do
    tools <- Simplifier.askMetadataTools
    case simplifySortInjections tools first second of
        Nothing ->
            Monad.Trans.lift
                (Monad.Unify.throwUnificationError
                    (unsupportedPatterns
                        "Unimplemented sort injection unification"
                        first
                        second
                    )
                )
        Just NotInjection -> empty
        Just NotMatching -> Monad.Trans.lift $ do
            Monad.Unify.explainBottom
                (Pretty.hsep
                    [ "Unification of sort injections failed due to mismatch."
                    , "This can happen either because one of them is a constructor"
                    , "or because their sort intersection is empty."
                    ]
                )
                first
                second
            Monad.Unify.scatter []
        Just
            (Matching SortInjectionMatch
                { injectionHead, sort, firstChild, secondChild }
            ) -> Monad.Trans.lift $ do
                merged <- termMerger firstChild secondChild
                if Pattern.isBottom merged
                    then do
                        Monad.Unify.explainBottom
                            (Pretty.hsep
                                [ "Unification of sort injections failed when"
                                , "merging application children:"
                                , "the result is bottom."
                                ]
                            )
                            first
                            second
                        Monad.Unify.scatter []
                    else
                        return $ applyInjection sort injectionHead <$> merged
  where
    applyInjection sort injectionHead term = mkApp sort injectionHead [term]

data SortInjectionMatch variable =
    SortInjectionMatch
        { injectionHead :: !SymbolOrAlias
        , sort :: !Sort
        , firstChild :: !(TermLike variable)
        , secondChild :: !(TermLike variable)
        }

data SortInjectionSimplification variable
  = NotInjection
  | NotMatching
  | Matching !(SortInjectionMatch variable)

simplifySortInjections
    :: forall variable
    .  Ord variable
    => SmtMetadataTools StepperAttributes
    -> TermLike variable
    -> TermLike variable
    -> Maybe (SortInjectionSimplification variable)
simplifySortInjections
    tools
    (App_
        firstHead@SymbolOrAlias
            { symbolOrAliasConstructor = firstConstructor
            , symbolOrAliasParams = [firstOrigin, firstDestination]
            }
        [firstChild])
    (App_
        secondHead@SymbolOrAlias
            { symbolOrAliasConstructor = secondConstructor
            , symbolOrAliasParams = [secondOrigin, secondDestination]
            }
        [secondChild]
    )
  | isFirstSortInjection && isSecondSortInjection =
    assert (firstHead /= secondHead)
    $ assert (firstDestination == secondDestination)
    $ assert (firstConstructor == secondConstructor)
    $ case () of
        _
          | firstOrigin `isSubsortOf` secondOrigin -> Just mergeFirstIntoSecond

          | secondOrigin `isSubsortOf` firstOrigin -> Just mergeSecondIntoFirst

          | isFirstConstructorLike || isSecondConstructorLike
            -> Just NotMatching

          | Set.null sortIntersection -> Just NotMatching

          | otherwise -> Nothing
  where
    subsorts = MetadataTools.subsorts tools

    firstHeadAttributes = MetadataTools.symAttributes tools firstHead
    secondHeadAttributes = MetadataTools.symAttributes tools secondHead

    Attribute.Symbol { sortInjection = SortInjection isFirstSortInjection } =
        firstHeadAttributes
    Attribute.Symbol { sortInjection = SortInjection isSecondSortInjection } =
        secondHeadAttributes

    isSubsortOf = MetadataTools.isSubsortOf tools

    isConstructorLike = isConstructorLikeTop tools . Recursive.project
    isFirstConstructorLike = isConstructorLike firstChild
    isSecondConstructorLike = isConstructorLike secondChild

    {- |
        Merge the terms inside a sort injection,

        \inj{src1, dst}(a) ∧ \inj{src2, dst}(b)
        ===
        \inj{src2, dst}(\inj{src1, src2}(a) ∧ b)

        when src1 is a subsort of src2.
     -}
    mergeFirstIntoSecond ::  SortInjectionSimplification variable
    mergeFirstIntoSecond =
        Matching SortInjectionMatch
            { injectionHead = SymbolOrAlias
                { symbolOrAliasConstructor = firstConstructor
                , symbolOrAliasParams = [secondOrigin, firstDestination]
                }
            , sort = firstDestination
            , firstChild = sortInjection firstOrigin secondOrigin firstChild
            , secondChild = secondChild
            }

    {- |
        Merge the terms inside a sort injection,

        \inj{src1, dst}(a) ∧ \inj{src2, dst}(b)
        ===
        \inj{src1, dst}(a ∧ \inj{src2, src1}(b))

        when src2 is a subsort of src1.
     -}
    mergeSecondIntoFirst :: SortInjectionSimplification variable
    mergeSecondIntoFirst =
        Matching SortInjectionMatch
            { injectionHead = SymbolOrAlias
                { symbolOrAliasConstructor = firstConstructor
                , symbolOrAliasParams = [firstOrigin, firstDestination]
                }
            , sort = firstDestination
            , firstChild = firstChild
            , secondChild = sortInjection secondOrigin firstOrigin secondChild
            }

    sortInjection
        :: Sort
        -> Sort
        -> TermLike variable
        -> TermLike variable
    sortInjection originSort destinationSort term =
        mkApp
            destinationSort
            SymbolOrAlias
                { symbolOrAliasConstructor = firstConstructor
                , symbolOrAliasParams = [originSort, destinationSort]
                }
            [term]
    firstSubsorts = subsorts firstOrigin
    secondSubsorts = subsorts secondOrigin
    sortIntersection = Set.intersection firstSubsorts secondSubsorts
simplifySortInjections _ _ _ = Just NotInjection

{- | Unify a constructor application pattern with a sort injection pattern.

Sort injections clash with constructors, so @constructorSortInjectionAndEquals@
returns @\\bottom@.

 -}
-- TODO (virgil): This implementation is provisional, we're not sure yet if sort
-- injection should always clash with constructors. We should clarify this.
constructorSortInjectionAndEquals
    ::  ( Eq variable
        , SortedVariable variable
        , Unparse variable
        , MonadUnify unifier
        )
    => TermLike variable
    -> TermLike variable
    -> MaybeT unifier (TermLike variable)
constructorSortInjectionAndEquals
    first@(App_ firstHead _)
    second@(App_ secondHead _)
  = do
    tools <- Simplifier.askMetadataTools
    let
        -- Are we asked to unify a constructor with a sort injection?
        isConstructorSortInjection =
            (||)
                (isConstructor   firstHead && isSortInjection secondHead)
                (isSortInjection firstHead && isConstructor   secondHead)
        isConstructor = give tools Attribute.isConstructor_
        isSortInjection = give tools Attribute.isSortInjection_
    Monad.guard isConstructorSortInjection
    assert (firstHead /= secondHead) $ Monad.Trans.lift $ do
        Monad.Unify.explainBottom
            "Cannot unify constructors with sort injections."
            first
            second
        Monad.Unify.scatter []
constructorSortInjectionAndEquals _ _ = empty

{-| Unify two constructor application patterns.

Assumes that the two patterns were already tested for equality and were found
to be different; therefore their conjunction is @\\bottom@.

 -}
constructorAndEqualsAssumesDifferentHeads
    ::  ( Eq variable
        , SortedVariable variable
        , Unparse variable
        , MonadUnify unifier
        )
    => TermLike variable
    -> TermLike variable
    -> MaybeT unifier (TermLike variable)
constructorAndEqualsAssumesDifferentHeads
    first@(App_ firstHead _)
    second@(App_ secondHead _)
  = do
    tools <- Simplifier.askMetadataTools
    let isConstructor = give tools Attribute.isConstructor_
    Monad.guard (isConstructor firstHead)
    Monad.guard (isConstructor secondHead)
    assert (firstHead /= secondHead) $ Monad.Trans.lift $ do
        Monad.Unify.explainBottom
            (Pretty.hsep
                [ "Cannot unify different constructors or"
                , "incompatible sort injections."
                ]
            )
            first
            second
        Monad.Unify.scatter []
constructorAndEqualsAssumesDifferentHeads _ _ = empty

{- | Unifcation or equality for a domain value pattern vs a constructor
application.

This unification case throws an error because domain values may not occur in a
sort with constructors.

-}
domainValueAndConstructorErrors
    :: Eq variable
    => Unparse variable
    => SortedVariable variable
    => SmtMetadataTools StepperAttributes
    -> TermLike variable
    -> TermLike variable
    -> Maybe (TermLike variable)
domainValueAndConstructorErrors
    tools
    term1@(DV_ _ _)
    term2@(App_ secondHead _)
    | give tools Attribute.isConstructor_ secondHead =
      error (unlines [ "Cannot handle DomainValue and Constructor:"
                     , unparseToString term1
                     , unparseToString term2
                     ]
            )
domainValueAndConstructorErrors
    tools
    term1@(Builtin_ _)
    term2@(App_ secondHead _)
    | give tools Attribute.isConstructor_ secondHead =
      error (unlines [ "Cannot handle builtin and Constructor:"
                     , unparseToString term1
                     , unparseToString term2
                     ]
            )
domainValueAndConstructorErrors
    tools
    term1@(App_ firstHead _)
    term2@(DV_ _ _)
    | give tools Attribute.isConstructor_ firstHead =
      error (unlines [ "Cannot handle Constructor and DomainValue:"
                     , unparseToString term1
                     , unparseToString term2
                     ]
            )
domainValueAndConstructorErrors
    tools
    term1@(App_ firstHead _)
    term2@(Builtin_ _)
    | give tools Attribute.isConstructor_ firstHead =
      error (unlines [ "Cannot handle Constructor and builtin:"
                     , unparseToString term1
                     , unparseToString term2
                     ]
            )
domainValueAndConstructorErrors _ _ _ = empty

{- | Unify two domain values.

The two patterns are assumed to be inequal; therefore this case always return
@\\bottom@.

See also: 'equalAndEquals'

-}
-- TODO (thomas.tuegel): This unification case assumes that \dv is injective,
-- but it is not.
domainValueAndEqualsAssumesDifferent
    :: Eq variable
    => SortedVariable variable
    => Unparse variable
    => MonadUnify unifier
    => TermLike variable
    -> TermLike variable
    -> MaybeT unifier (TermLike variable)
domainValueAndEqualsAssumesDifferent
    first@(DV_ _ _)
    second@(DV_ _ _)
  = Monad.Trans.lift $ cannotUnifyDomainValues first second
domainValueAndEqualsAssumesDifferent
    first@(Builtin_ (Domain.BuiltinBool _))
    second@(Builtin_ (Domain.BuiltinBool _))
  = Monad.Trans.lift $ cannotUnifyDomainValues first second
domainValueAndEqualsAssumesDifferent
    first@(Builtin_ (Domain.BuiltinInt _))
    second@(Builtin_ (Domain.BuiltinInt _))
  = Monad.Trans.lift $ cannotUnifyDomainValues first second
domainValueAndEqualsAssumesDifferent
    first@(Builtin_ (Domain.BuiltinString _))
    second@(Builtin_ (Domain.BuiltinString _))
  = Monad.Trans.lift $ cannotUnifyDomainValues first second
domainValueAndEqualsAssumesDifferent _ _ = empty

cannotUnifyDistinctDomainValues :: Pretty.Doc ()
cannotUnifyDistinctDomainValues = "Cannot unify distinct domain values."

cannotUnifyDomainValues
    :: Eq variable
    => SortedVariable variable
    => Unparse variable
    => MonadUnify unifier
    => TermLike variable
    -> TermLike variable
    -> unifier (TermLike variable)
cannotUnifyDomainValues first second =
    assert (first /= second) $ do
        Monad.Unify.explainBottom
            cannotUnifyDistinctDomainValues
            first
            second
        Monad.Unify.scatter []

{-| Unify two literal strings.

The two patterns are assumed to be inequal; therefore this case always returns
@\\bottom@.

See also: 'equalAndEquals'

 -}
stringLiteralAndEqualsAssumesDifferent
    :: Eq variable
    => SortedVariable variable
    => Unparse variable
    => MonadUnify unifier
    => TermLike variable
    -> TermLike variable
    -> MaybeT unifier (TermLike variable)
stringLiteralAndEqualsAssumesDifferent
    first@(StringLiteral_ _)
    second@(StringLiteral_ _)
  = Monad.Trans.lift $ cannotUnifyDomainValues first second
stringLiteralAndEqualsAssumesDifferent _ _ = empty

{-| Unify two literal characters.

The two patterns are assumed to be inequal; therefore this case always returns
@\\bottom@.

See also: 'equalAndEquals'

 -}
charLiteralAndEqualsAssumesDifferent
    :: Eq variable
    => SortedVariable variable
    => Unparse variable
    => MonadUnify unifier
    => TermLike variable
    -> TermLike variable
    -> MaybeT unifier (TermLike variable)
charLiteralAndEqualsAssumesDifferent
    first@(CharLiteral_ _)
    second@(CharLiteral_ _)
  = Monad.Trans.lift $ cannotUnifyDomainValues first second
charLiteralAndEqualsAssumesDifferent _ _ = empty

{- | Unify any two function patterns.

The function patterns are unified by creating an @\\equals@ predicate.

-}
functionAnd
    ::  ( SortedVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        )
    => SmtMetadataTools StepperAttributes
    -> TermLike variable
    -> TermLike variable
    -> Maybe (Pattern variable)
functionAnd
    tools
    first
    second
  | isFunctionPattern tools first
  , isFunctionPattern tools second =
    return Conditional
        { term = first  -- different for Equals
        -- Ceil predicate not needed since first being
        -- bottom will make the entire term bottom. However,
        -- one must be careful to not just drop the term.
        , predicate = makeEqualsPredicate first second
        , substitution = mempty
        }
  | otherwise = empty
