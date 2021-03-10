{-# LANGUAGE Strict #-}

{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
-}
module Kore.Step.Simplification.Pattern (
    simplifyTopConfiguration,
    simplify,
    makeEvaluate,
) where

import Prelude.Kore

import qualified Kore.Internal.Condition as Condition
import qualified Kore.Internal.Conditional as Conditional
import Kore.Internal.OrPattern (
    OrPattern,
 )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern (
    Conditional (..),
    Pattern,
 )
import Kore.Internal.SideCondition (
    SideCondition,
 )
import qualified Kore.Internal.SideCondition as SideCondition (
    andCondition,
    top,
 )
import Kore.Internal.Substitution (
    toMap,
 )
import Kore.Internal.TermLike (
    pattern Exists_,
 )
import Kore.Rewriting.RewritingVariable (
    RewritingVariableName,
 )
import Kore.Step.Simplification.Simplify (
    MonadSimplify,
    simplifyCondition,
    simplifyConditionalTerm,
 )
import Kore.Substitute (
    substitute,
 )

-- | Simplifies the pattern and removes the exists quantifiers at the top.
simplifyTopConfiguration ::
    forall simplifier.
    MonadSimplify simplifier =>
    Pattern RewritingVariableName ->
    simplifier (OrPattern RewritingVariableName)
simplifyTopConfiguration patt = do
    simplified <- simplify patt
    return (OrPattern.map removeTopExists simplified)
  where
    removeTopExists ::
        Pattern RewritingVariableName -> Pattern RewritingVariableName
    removeTopExists p@Conditional{term = Exists_ _ _ quantified} =
        removeTopExists p{term = quantified}
    removeTopExists p = p

-- | Simplifies an 'Pattern', returning an 'OrPattern'.
simplify ::
    MonadSimplify simplifier =>
    Pattern RewritingVariableName ->
    simplifier (OrPattern RewritingVariableName)
simplify = makeEvaluate SideCondition.top

{- | Simplifies a 'Pattern' with a custom 'SideCondition'.
This should only be used when it's certain that the
'SideCondition' was not created from the 'Condition' of
the 'Pattern'.
-}
makeEvaluate ::
    MonadSimplify simplifier =>
    SideCondition RewritingVariableName ->
    Pattern RewritingVariableName ->
    simplifier (OrPattern RewritingVariableName)
makeEvaluate sideCondition pattern' =
    OrPattern.observeAllT $ do
        withSimplifiedCondition <- simplifyCondition sideCondition pattern'
        let (term, simplifiedCondition) =
                Conditional.splitTerm withSimplifiedCondition
            term' = substitute (toMap $ substitution simplifiedCondition) term
            simplifiedCondition' =
                -- Combine the predicate and the substitution. The substitution
                -- has already been applied to the term being simplified. This
                -- is only to make SideCondition.andCondition happy, below,
                -- because there might be substitution variables in
                -- sideCondition. That's allowed because we are only going to
                -- send the side condition to the solver, but we should probably
                -- fix SideCondition.andCondition instead.
                simplifiedCondition
                    & Condition.toPredicate
                    & Condition.fromPredicate
            termSideCondition =
                sideCondition `SideCondition.andCondition` simplifiedCondition'
        simplifiedTerm <- simplifyConditionalTerm termSideCondition term'
        let simplifiedPattern =
                Conditional.andCondition simplifiedTerm simplifiedCondition
        simplifyCondition sideCondition simplifiedPattern
