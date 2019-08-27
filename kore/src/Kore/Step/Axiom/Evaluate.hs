{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}
module Kore.Step.Axiom.Evaluate
    ( evaluateAxioms
    ) where

import qualified Control.Monad as Monad
import qualified Data.Foldable as Foldable
import           Data.Function

import qualified Kore.Attribute.Axiom as Attribute.Axiom
import qualified Kore.Attribute.Axiom.Concrete as Attribute.Axiom.Concrete
import           Kore.Internal.Pattern
                 ( Pattern )
import qualified Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
                 ( TermLike )
import qualified Kore.Internal.TermLike as TermLike
import           Kore.Step.Axiom.Matcher
                 ( matchIncremental )
import           Kore.Step.Remainder
                 ( ceilChildOfApplicationOrTop )
import qualified Kore.Step.Result as Result
import           Kore.Step.Rule
                 ( EqualityRule (..) )
import qualified Kore.Step.Rule as RulePattern
                 ( RulePattern (..), mapVariables )
import           Kore.Step.Simplification.Data
import qualified Kore.Step.Simplification.Data as AttemptedAxiom
                 ( AttemptedAxiom (..), maybeNotApplicable )
import qualified Kore.Step.Simplification.OrPattern as OrPattern
import           Kore.Step.Step
                 ( UnificationProcedure (..) )
import qualified Kore.Step.Step as Step
import qualified Kore.Unification.Unify as Monad.Unify
import           Kore.Unparser
import           Kore.Variables.Fresh

evaluateAxioms
    :: forall variable simplifier
    .   ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        , MonadSimplify simplifier
        )
    => [EqualityRule Variable]
    -> TermLike variable
    -> simplifier (AttemptedAxiom variable)
evaluateAxioms
    definitionRules
    patt
  | any ruleIsConcrete definitionRules
  , not (TermLike.isConcrete patt)
  = return AttemptedAxiom.NotApplicable
  | otherwise
  = AttemptedAxiom.maybeNotApplicable $ do
    let
        -- TODO (thomas.tuegel): Figure out how to get the initial conditions
        -- and apply them here, to remove remainder branches sooner.
        expanded :: Pattern variable
        expanded = Pattern.fromTermLike patt

    results <- applyRules expanded (map unwrapEqualityRule definitionRules)
    Monad.guard (any Result.hasResults results)
    mapM_ rejectNarrowing results

    ceilChild <- ceilChildOfApplicationOrTop patt
    let
        result =
            Result.mergeResults results
            & Result.mapConfigs
                keepResultUnchanged
                ( markRemainderEvaluated
                . introduceDefinedness ceilChild
                )
        keepResultUnchanged = id
        introduceDefinedness = flip Pattern.andCondition
        markRemainderEvaluated = fmap TermLike.mkEvaluated

    AttemptedAxiomResults
        <$> OrPattern.simplifyPredicatesWithSmt (Step.gatherResults result)
        <*> OrPattern.simplifyPredicatesWithSmt (Step.remainders result)

  where
    ruleIsConcrete =
        Attribute.Axiom.Concrete.isConcrete
        . Attribute.Axiom.concrete
        . RulePattern.attributes
        . getEqualityRule

    unwrapEqualityRule (EqualityRule rule) =
        RulePattern.mapVariables fromVariable rule

    rejectNarrowing (Result.results -> results) =
        (Monad.guard . not) (Foldable.any Step.isNarrowingResult results)

    applyRules initial rules =
        Monad.Unify.maybeUnifierT
        $ Step.applyRulesSequence unificationProcedure initial rules

    ignoreUnificationErrors unification pattern1 pattern2 =
        Monad.Unify.runUnifierT (unification pattern1 pattern2)
        >>= either (couldNotMatch pattern1 pattern2) Monad.Unify.scatter

    couldNotMatch pattern1 pattern2 _ =
        Monad.Unify.explainAndReturnBottom
            "Could not match patterns"
            pattern1
            pattern2

    unificationProcedure =
        UnificationProcedure (ignoreUnificationErrors matchIncremental)
