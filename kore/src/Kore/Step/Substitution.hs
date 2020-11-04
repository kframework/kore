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
    ( mergePredicatesAndSubstitutions
    , normalize
    ) where

import Prelude.Kore

import Kore.Internal.Condition
    ( Condition
    , Conditional (..)
    )
import qualified Kore.Internal.MultiOr as MultiOr
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( Predicate
    )
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.SideCondition
    ( SideCondition
    )
import Kore.Internal.Substitution
    ( Substitution
    )
import Kore.Step.Simplification.Simplify as Simplifier
import Kore.Step.Simplification.SubstitutionSimplifier
    ( SubstitutionSimplifier (..)
    )
import qualified Kore.Step.Simplification.SubstitutionSimplifier as SubstitutionSimplifier
import Kore.TopBottom
    ( TopBottom
    )
import Logic

-- | Normalize the substitution and predicate of 'expanded'.
normalize
    :: forall variable term simplifier
    .  InternalVariable variable
    => Ord term
    => TopBottom term
    => MonadSimplify simplifier
    => SideCondition variable
    -> Conditional variable term
    -> LogicT simplifier (Conditional variable term)
normalize sideCondition conditional@Conditional { substitution } = do
    results <- simplifySubstitution sideCondition substitution & lift
    scatter (MultiOr.map applyTermPredicate results)
  where
    applyTermPredicate =
        Pattern.andCondition conditional { substitution = mempty }
    SubstitutionSimplifier { simplifySubstitution } =
        SubstitutionSimplifier.substitutionSimplifier

{-|'mergePredicatesAndSubstitutions' merges a list of substitutions into
a single one, then merges the merge side condition and the given condition list
into a condition.

If it does not know how to merge the substitutions, it will transform them into
predicates and redo the merge.
-}
mergePredicatesAndSubstitutions
    :: forall variable simplifier
    .  InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> [Predicate variable]
    -> [Substitution variable]
    -> LogicT simplifier (Condition variable)
mergePredicatesAndSubstitutions topCondition predicates substitutions =
    simplifyCondition
        topCondition
        Conditional
            { term = ()
            , predicate = Predicate.makeMultipleAndPredicate predicates
            , substitution = fold substitutions
            }
