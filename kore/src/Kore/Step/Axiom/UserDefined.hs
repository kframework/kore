{-|
Module      : Kore.Step.Axiom.UserDefined
Description : Evaluates user-defined functions in a pattern.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Axiom.UserDefined
    ( TermLikeSimplifier
    , equalityRuleEvaluator
    ) where

import qualified Kore.Attribute.Axiom as Attribute
import qualified Kore.Attribute.Axiom.Concrete as Axiom.Concrete
import           Kore.Attribute.Symbol
                 ( StepperAttributes )
import           Kore.IndexedModule.MetadataTools
                 ( SmtMetadataTools )
import qualified Kore.Internal.MultiOr as MultiOr
import qualified Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
import           Kore.Step.Axiom.Data as AttemptedAxiom
                 ( AttemptedAxiom (..) )
import           Kore.Step.Axiom.Data as AttemptedAxiomResults
                 ( AttemptedAxiomResults (..) )
import           Kore.Step.Axiom.Data
                 ( AttemptedAxiomResults (AttemptedAxiomResults),
                 BuiltinAndAxiomSimplifierMap )
import           Kore.Step.Axiom.Matcher
                 ( matchAsUnification )
import           Kore.Step.Rule
                 ( EqualityRule (EqualityRule), RulePattern (..) )
import qualified Kore.Step.Rule as RulePattern
import           Kore.Step.Simplification.Data
                 ( PredicateSimplifier, Simplifier, TermLikeSimplifier )
import qualified Kore.Step.Simplification.Pattern as Pattern
import           Kore.Step.Step
                 ( UnificationProcedure (..) )
import qualified Kore.Step.Step as Step
import qualified Kore.Syntax.Pattern as Pure
import qualified Kore.Unification.Unify as Monad.Unify
import           Kore.Unparser
                 ( Unparse )
import           Kore.Variables.Fresh

{-| Evaluates a pattern using user-defined axioms. After
evaluating the pattern, it tries to re-apply all axioms on the result.
-}
equalityRuleEvaluator
    ::  forall variable.
        ( FreshVariable variable
        , SortedVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        )
    => EqualityRule Variable
    -- ^ Axiom defining the current function.
    -> SmtMetadataTools StepperAttributes
    -- ^ Tools for finding additional information about patterns
    -- such as their sorts, whether they are constructors or hooked.
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions in patterns
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from axiom IDs to axiom evaluators
    -> TermLike variable
    -- ^ The function on which to evaluate the current function.
    -> Simplifier (AttemptedAxiom variable)
equalityRuleEvaluator
    (EqualityRule rule)
    tools
    substitutionSimplifier
    simplifier
    axiomIdToSimplifier
    patt
  -- TODO(traiansf): never apply smt-lemma axioms,
  -- neither as simplification rules nor as function definition rules
  | Axiom.Concrete.isConcrete (Attribute.concrete $ attributes rule)
  , not (Pure.isConcrete patt)
  = notApplicable
  | otherwise = do
    result <- applyRule patt rule
    case result of
        Left _        -> notApplicable
        Right results -> AttemptedAxiom.Applied <$> simplifyResults results
  where
    notApplicable = return AttemptedAxiom.NotApplicable

    unificationProcedure = UnificationProcedure matchAsUnification

    applyRule patt' rule' =
        Monad.Unify.runUnifier $
        Step.applyRulesInParallel
            tools
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier
            unificationProcedure
            [RulePattern.mapVariables fromVariable rule']
            (Pattern.fromTermLike patt')

    simplifyOrPatterns unsimplified =
        MultiOr.filterOr
        <$> traverse simplifyPattern unsimplified

    simplifyPattern config =
        Pattern.simplifyPredicate
            tools
            substitutionSimplifier
            simplifier
            axiomIdToSimplifier
            config

    simplifyResults
        :: Step.Results variable
        -> Simplifier (AttemptedAxiomResults variable)
    simplifyResults stepResults = do
        results <- simplifyOrPatterns $ Step.gatherResults stepResults
        remainders <- simplifyOrPatterns $ Step.remainders stepResults
        return AttemptedAxiomResults { results, remainders }
