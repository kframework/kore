{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

-}
module Kore.Step.Simplification.TermLike
    ( simplify
    , simplifyToOr
    , simplifyInternal
    ) where

import           Control.Error
                 ( MaybeT )
import qualified Control.Error as Error
import qualified Control.Monad as Monad
import           Control.Monad.State.Strict
                 ( StateT, evalStateT )
import qualified Control.Monad.State.Strict as Monad.State
import qualified Control.Monad.Trans as Monad.Trans
import           Data.Function
import qualified Data.Functor.Foldable as Recursive

import           Kore.Internal.OrPattern
                 ( OrPattern )
import qualified Kore.Internal.OrPattern as OrPattern
import           Kore.Internal.Pattern
                 ( Pattern )
import qualified Kore.Internal.Pattern as Pattern
import           Kore.Internal.Predicate
                 ( Predicate )
import qualified Kore.Internal.Predicate as Predicate
import           Kore.Internal.TermLike
import qualified Kore.Step.Function.Evaluator as Evaluator
import qualified Kore.Step.Simplification.And as And
                 ( simplify )
import qualified Kore.Step.Simplification.Application as Application
                 ( simplify )
import qualified Kore.Step.Simplification.Bottom as Bottom
                 ( simplify )
import qualified Kore.Step.Simplification.Builtin as Builtin
                 ( simplify )
import qualified Kore.Step.Simplification.Ceil as Ceil
                 ( simplify )
import qualified Kore.Step.Simplification.CharLiteral as CharLiteral
                 ( simplify )
import           Kore.Step.Simplification.Data
import qualified Kore.Step.Simplification.DomainValue as DomainValue
                 ( simplify )
import qualified Kore.Step.Simplification.Equals as Equals
                 ( simplify )
import qualified Kore.Step.Simplification.Exists as Exists
                 ( simplify )
import qualified Kore.Step.Simplification.Floor as Floor
                 ( simplify )
import qualified Kore.Step.Simplification.Forall as Forall
                 ( simplify )
import qualified Kore.Step.Simplification.Iff as Iff
                 ( simplify )
import qualified Kore.Step.Simplification.Implies as Implies
                 ( simplify )
import qualified Kore.Step.Simplification.In as In
                 ( simplify )
import qualified Kore.Step.Simplification.Inhabitant as Inhabitant
                 ( simplify )
import qualified Kore.Step.Simplification.Mu as Mu
                 ( simplify )
import qualified Kore.Step.Simplification.Next as Next
                 ( simplify )
import qualified Kore.Step.Simplification.Not as Not
                 ( simplify )
import qualified Kore.Step.Simplification.Nu as Nu
                 ( simplify )
import qualified Kore.Step.Simplification.Or as Or
                 ( simplify )
import qualified Kore.Step.Simplification.Rewrites as Rewrites
                 ( simplify )
import qualified Kore.Step.Simplification.StringLiteral as StringLiteral
                 ( simplify )
import qualified Kore.Step.Simplification.Top as Top
                 ( simplify )
import qualified Kore.Step.Simplification.Variable as Variable
                 ( simplify )
import           Kore.Unparser
import           Kore.Variables.Fresh

-- TODO(virgil): Add a Simplifiable class and make all pattern types
-- instances of that.

{-|'simplify' simplifies a `TermLike`, returning a 'Pattern'.
-}
simplify
    ::  ( SortedVariable variable
        , Show variable
        , Ord variable
        , Unparse variable
        , FreshVariable variable
        )
    => TermLike variable
    -> Simplifier (Pattern variable)
simplify patt = do
    orPatt <- simplifyToOr patt
    return (OrPattern.toPattern orPatt)

{-|'simplifyToOr' simplifies a TermLike variable, returning an
'OrPattern'.
-}
simplifyToOr
    ::  forall variable simplifier
    .   (FreshVariable variable, SortedVariable variable)
    =>  (Show variable, Unparse variable)
    =>  MonadSimplify simplifier
    =>  TermLike variable
    ->  simplifier (OrPattern variable)
simplifyToOr =
    gatherPatterns . begin . wrapper . Pattern.fromTermLike
  where
    begin = flip evalStateT True

    true :: forall a m. Monad m => a -> MaybeT (StateT Bool m) a
    true a = do
        Monad.State.put True
        return a

    false :: forall a m. Monad m => a -> MaybeT (StateT Bool m) a
    false a = do
        Monad.guard =<< Monad.State.get
        Monad.State.put False
        return a

    wrapper
        :: Pattern variable
        -> StateT Bool (BranchT simplifier) (Pattern variable)
    wrapper original =
        worker original
        & Error.maybeT (return original) wrapper

    worker
        :: Pattern variable
        -> MaybeT (StateT Bool (BranchT simplifier)) (Pattern variable)
    worker original = do
        let (termLike, predicate) = Pattern.splitTerm original
            orOriginal = OrPattern.fromPattern original
        orPattern <-
            Evaluator.evaluateOnce predicate termLike
            & Error.maybeT (false orOriginal) true
        evaluated <- scatter' orPattern
        simplifyPatternInternal evaluated >>= scatter'

    scatter'
        :: OrPattern variable
        -> MaybeT (StateT Bool (BranchT simplifier)) (Pattern variable)
    scatter' = Monad.Trans.lift . Monad.Trans.lift . scatter

simplifyPatternInternal
    ::  forall variable simplifier
    .   ( SortedVariable variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , MonadSimplify simplifier
        )
    => Pattern variable
    -> simplifier (OrPattern variable)
simplifyPatternInternal (Pattern.splitTerm -> (termLike, predicate)) =
    -- TODO: Figure out how to simplify the predicate.
    simplifyInternalExt predicate termLike

simplifyInternal
    ::  forall variable simplifier
    .   ( SortedVariable variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , MonadSimplify simplifier
        )
    => TermLike variable
    -> simplifier (OrPattern variable)
simplifyInternal = simplifyInternalExt Predicate.top

simplifyInternalExt
    ::  forall variable simplifier
    .   ( SortedVariable variable
        , Show variable
        , Unparse variable
        , FreshVariable variable
        , MonadSimplify simplifier
        )
    => Predicate variable
    -> TermLike variable
    -> simplifier (OrPattern variable)
simplifyInternalExt predicate =
    Monad.liftM (fmap andPredicate) . simplifyInternalWorker
  where
    andPredicate = flip Pattern.andCondition predicate

    simplifyChildren
        :: Traversable t
        => t (TermLike variable)
        -> simplifier (t (OrPattern variable))
    simplifyChildren = traverse simplifyInternalWorker

    simplifyInternalWorker termLike =
        let doNotSimplify = return (OrPattern.fromTermLike termLike)
            (_ :< termLikeF) = Recursive.project termLike
        in case termLikeF of
            -- Unimplemented cases
            ApplyAliasF _ -> doNotSimplify
            -- Do not simplify evaluated patterns.
            EvaluatedF  _ -> doNotSimplify
            --
            AndF andF ->
                And.simplify =<< simplifyChildren andF
            ApplySymbolF applySymbolF ->
                Application.simplify =<< simplifyChildren applySymbolF
            CeilF ceilF ->
                Ceil.simplify =<< simplifyChildren ceilF
            EqualsF equalsF ->
                Equals.simplify =<< simplifyChildren equalsF
            ExistsF existsF ->
                Exists.simplify =<< simplifyChildren existsF
            IffF iffF ->
                Iff.simplify =<< simplifyChildren iffF
            ImpliesF impliesF ->
                Implies.simplify =<< simplifyChildren impliesF
            InF inF ->
                In.simplify =<< simplifyChildren inF
            NotF notF ->
                Not.simplify =<< simplifyChildren notF
            --
            BottomF bottomF -> Bottom.simplify <$> simplifyChildren bottomF
            BuiltinF builtinF -> Builtin.simplify <$> simplifyChildren builtinF
            DomainValueF domainValueF ->
                DomainValue.simplify <$> simplifyChildren domainValueF
            FloorF floorF -> Floor.simplify <$> simplifyChildren floorF
            ForallF forallF -> Forall.simplify <$> simplifyChildren forallF
            InhabitantF inhF -> Inhabitant.simplify <$> simplifyChildren inhF
            MuF muF -> Mu.simplify <$> simplifyChildren muF
            NuF nuF -> Nu.simplify <$> simplifyChildren nuF
            -- TODO(virgil): Move next up through patterns.
            NextF nextF -> Next.simplify <$> simplifyChildren nextF
            OrF orF -> Or.simplify <$> simplifyChildren orF
            RewritesF rewritesF ->
                Rewrites.simplify <$> simplifyChildren rewritesF
            StringLiteralF stringLiteralF ->
                StringLiteral.simplify <$> simplifyChildren stringLiteralF
            CharLiteralF charLiteralF ->
                CharLiteral.simplify <$> simplifyChildren charLiteralF
            TopF topF -> Top.simplify <$> simplifyChildren topF
            --
            VariableF variableF -> return $ Variable.simplify variableF
