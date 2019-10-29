{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
-}

module Kore.Step.Rule.Simplify
    ( simplifyOnePathRuleLhs
    ) where

import qualified Kore.Internal.Condition as Condition
    ( fromPredicate
    )
import Kore.Internal.Conditional
    ( Conditional (Conditional)
    )
import qualified Kore.Internal.Conditional as Conditional.DoNotUse
    ( Conditional (..)
    )
import qualified Kore.Internal.Conditional as Conditional
    ( withCondition
    )
import Kore.Internal.MultiAnd
    ( MultiAnd
    )
import qualified Kore.Internal.MultiAnd as MultiAnd
    ( make
    )
import qualified Kore.Internal.MultiOr as MultiOr
    ( extractPatterns
    )
import Kore.Internal.Pattern
    ( Pattern
    )
import Kore.Predicate.Predicate
    ( makeAndPredicate
    , makeCeilPredicate
    )
import Kore.Step.Rule
    ( OnePathRule (..)
    , RulePattern (RulePattern)
    )
import qualified Kore.Step.Rule as RulePattern
    ( RulePattern (..)
    , applySubstitution
    )
import Kore.Step.Simplification.OrPattern
    ( simplifyConditionsWithSmt
    )
import qualified Kore.Step.Simplification.Pattern as Pattern
    ( simplifyAndRemoveTopExists
    )
import Kore.Step.Simplification.Simplify
    ( MonadSimplify
    , SimplifierVariable
    )

simplifyOnePathRuleLhs
    ::  ( MonadSimplify simplifier
        , SimplifierVariable variable
        )
    => OnePathRule variable
    -> simplifier (MultiAnd (OnePathRule variable))
simplifyOnePathRuleLhs (OnePathRule rule) = do
    simplifiedList <- simplifyRuleLhs rule
    return (fmap OnePathRule simplifiedList)

simplifyRuleLhs
    :: forall simplifier variable
    .   ( MonadSimplify simplifier
        , SimplifierVariable variable
        )
    => RulePattern variable
    -> simplifier (MultiAnd (RulePattern variable))
simplifyRuleLhs rule@(RulePattern _ _ _ _ _ _) = do
    let lhsPredicate =
            makeAndPredicate
                requires
                (makeCeilPredicate left)
        definedLhs =
            Conditional.withCondition left
            $ Condition.fromPredicate lhsPredicate
    simplifiedTerms <- Pattern.simplifyAndRemoveTopExists definedLhs
    fullySimplified <- simplifyConditionsWithSmt lhsPredicate simplifiedTerms
    let rules = map (setRuleLeft rule) (MultiOr.extractPatterns fullySimplified)
    return (MultiAnd.make rules)
  where
    RulePattern {left, requires} = rule

    setRuleLeft
        :: RulePattern variable
        -> Pattern variable
        -> RulePattern variable
    setRuleLeft
        rulePattern
        Conditional {term, predicate, substitution}
      =
        RulePattern.applySubstitution
            substitution
            rulePattern
                { RulePattern.left = term
                , RulePattern.requires = predicate
                }
