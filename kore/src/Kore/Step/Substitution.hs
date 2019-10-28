{-|
Module      : Kore.Step.Substitution
Description : Tools for manipulating substitutions when doing Kore execution.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Substitution
    ( PredicateMerger (..)
    , createLiftedPredicatesAndSubstitutionsMerger
    , createPredicatesAndSubstitutionsMerger
    , createPredicatesAndSubstitutionsMergerExcept
    , mergePredicatesAndSubstitutions
    , normalize
    , normalizeExcept
    ) where

import qualified Control.Monad.Trans.Class as Monad.Trans
import qualified Data.Foldable as Foldable
import GHC.Stack
    ( HasCallStack
    )

import Branch
import Kore.Internal.Condition
    ( Condition
    , Conditional (..)
    )
import qualified Kore.Internal.Condition as Condition
import qualified Kore.Internal.Conditional as Conditional
import Kore.Logger
    ( LogMessage
    , WithLog
    )
import Kore.Predicate.Predicate
    ( Predicate
    )
import qualified Kore.Predicate.Predicate as Predicate
import Kore.Step.Simplification.Simplify as Simplifier
import Kore.Unification.Substitution
    ( Substitution
    )
import qualified Kore.Unification.UnifierImpl as Unification
import Kore.Unification.Unify
    ( MonadUnify
    , SimplifierVariable
    )
import qualified Kore.Unification.Unify as Monad.Unify

newtype PredicateMerger variable m =
    PredicateMerger
    (  [Predicate variable]
    -> [Substitution variable]
    -> m (Condition variable)
    )

-- | Normalize the substitution and predicate of 'expanded'.
normalize
    :: forall variable term simplifier
    .  (SimplifierVariable variable, MonadSimplify simplifier)
    => Conditional variable term
    -> BranchT simplifier (Conditional variable term)
normalize Conditional { term, predicate, substitution } = do
    -- We collect all the results here because we should promote the
    -- substitution to the predicate when there is an error on *any* branch.
    results <-
        Monad.Trans.lift
        $ Monad.Unify.runUnifierT
        $ Unification.normalizeOnce
            Conditional { term = (), predicate, substitution }
    case results of
        Right normal -> scatter (applyTerm <$> normal)
        Left _ -> do
            let combined =
                    Condition.fromPredicate
                    . Predicate.markSimplified
                    $ Predicate.makeAndPredicate predicate
                    -- TODO (thomas.tuegel): Promoting the entire substitution
                    -- to the predicate is a problem. We should only promote the
                    -- part which has cyclic dependencies.
                    $ Predicate.fromSubstitution substitution
            return (Conditional.withCondition term combined)
  where
    applyTerm predicated = predicated { term }

normalizeExcept
    ::  forall unifier variable
    .   ( SimplifierVariable variable
        , MonadUnify unifier
        , WithLog LogMessage unifier
        )
    => Condition variable
    -> unifier (Condition variable)
normalizeExcept = Unification.normalizeExcept

{-|'mergePredicatesAndSubstitutions' merges a list of substitutions into
a single one, then merges the merge side condition and the given condition list
into a condition.

If it does not know how to merge the substitutions, it will transform them into
predicates and redo the merge.

hs-boot: Please remember to update the hs-boot file when changing the signature.
-}
mergePredicatesAndSubstitutions
    ::  forall variable simplifier
    .   ( SimplifierVariable variable
        , MonadSimplify simplifier
        , HasCallStack
        , WithLog LogMessage simplifier
        )
    => [Predicate variable]
    -> [Substitution variable]
    -> BranchT simplifier (Condition variable)
mergePredicatesAndSubstitutions predicates substitutions = do
    simplifyCondition Conditional
        { term = ()
        , predicate = Predicate.makeMultipleAndPredicate predicates
        , substitution = Foldable.fold substitutions
        }

{-| Creates a 'PredicateMerger' that returns errors on unifications it
can't handle.
-}
createPredicatesAndSubstitutionsMergerExcept
    ::  forall variable unifier
    .   ( SimplifierVariable variable
        , MonadUnify unifier
        , WithLog LogMessage unifier
        )
    => PredicateMerger variable unifier
createPredicatesAndSubstitutionsMergerExcept =
    PredicateMerger worker
  where
    worker
        :: [Predicate variable]
        -> [Substitution variable]
        -> unifier (Condition variable)
    worker predicates substitutions = do
        let merged =
                (Condition.fromPredicate <$> predicates)
                <> (Condition.fromSubstitution <$> substitutions)
        normalizeExcept (Foldable.fold merged)

{-| Creates a 'PredicateMerger' that creates predicates for
unifications it can't handle.
-}
createPredicatesAndSubstitutionsMerger
    :: forall variable simplifier
    .  (SimplifierVariable variable, MonadSimplify simplifier)
    => PredicateMerger variable (BranchT simplifier)
createPredicatesAndSubstitutionsMerger =
    PredicateMerger worker
  where
    worker
        :: [Predicate variable]
        -> [Substitution variable]
        -> BranchT simplifier (Condition variable)
    worker predicates substitutions = do
        let merged =
                (Condition.fromPredicate <$> predicates)
                <> (Condition.fromSubstitution <$> substitutions)
        normalize (Foldable.fold merged)

{-| Creates a 'PredicateMerger' that creates predicates for
unifications it can't handle and whose result is in any monad transformer
over the base monad.
-}
createLiftedPredicatesAndSubstitutionsMerger
    ::  forall variable unifier
    .   ( SimplifierVariable variable
        , MonadUnify unifier
        , WithLog LogMessage unifier
        )
    => PredicateMerger variable unifier
createLiftedPredicatesAndSubstitutionsMerger =
    PredicateMerger worker
  where
    worker
        :: [Predicate variable]
        -> [Substitution variable]
        -> unifier (Condition variable)
    worker predicates substitutions = do
        let merged =
                (Condition.fromPredicate <$> predicates)
                <> (Condition.fromSubstitution <$> substitutions)
        normalizeExcept (Foldable.fold merged)
