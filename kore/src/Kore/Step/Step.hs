{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

Unification of rules (used for stepping with rules or equations)

 -}
module Kore.Step.Step
    ( UnifiedRule
    , Result
    , Results
    , Renaming
    , UnifyingRule (..)
    , InstantiationFailure (..)
    , unifyRules
    , unifyRule
    , applyInitialConditions
    , applyRemainder
    , simplifyPredicate
    , targetRuleVariables
    , toConfigurationVariables
    , toConfigurationVariablesCondition
    , unTargetRule
    , assertFunctionLikeResults
    , checkFunctionLike
    , wouldNarrowWith
    -- * Re-exports
    , UnificationProcedure (..)
    -- Below exports are just for tests
    , Step.gatherResults
    , Step.remainders
    , Step.result
    , Step.results
    ) where

import Prelude.Kore

import qualified Data.Foldable as Foldable
import Data.Map.Strict
    ( Map
    )
import qualified Data.Map.Strict as Map
import Data.Set
    ( Set
    )
import qualified Data.Set as Set
import qualified Data.Text.Prettyprint.Doc as Pretty

import Branch
    ( BranchT
    )
import qualified Branch
import Kore.Attribute.Pattern.FreeVariables
    ( FreeVariables (..)
    , HasFreeVariables (freeVariables)
    )
import qualified Kore.Attribute.Pattern.FreeVariables as FreeVariables
import Kore.Internal.Condition
    ( Condition
    )
import qualified Kore.Internal.Condition as Condition
import Kore.Internal.Conditional
    ( Conditional (Conditional)
    )
import qualified Kore.Internal.Conditional as Conditional
import qualified Kore.Internal.MultiOr as MultiOr
import Kore.Internal.OrCondition
    ( OrCondition
    )
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( Predicate
    )
import Kore.Internal.SideCondition
    ( SideCondition
    )
import qualified Kore.Internal.SideCondition as SideCondition
    ( andCondition
    , mapVariables
    )
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
    ( ElementVariable
    , InternalVariable
    , SetVariable
    , SortedVariable
    , TermLike
    )
import qualified Kore.Internal.TermLike as TermLike
import qualified Kore.Step.Result as Result
import qualified Kore.Step.Result as Results
import qualified Kore.Step.Result as Step
import Kore.Step.Simplification.Simplify
    ( MonadSimplify
    )
import qualified Kore.Step.Simplification.Simplify as Simplifier
import qualified Kore.Step.SMT.Evaluator as SMT.Evaluator
import qualified Kore.TopBottom as TopBottom
import Kore.Unification.UnificationProcedure
import Kore.Unparser
import Kore.Variables.Fresh
    ( FreshPartialOrd
    )
import Kore.Variables.Target
    ( Target
    )
import qualified Kore.Variables.Target as Target
import Kore.Variables.UnifiedVariable
    ( UnifiedVariable
    )

type UnifiedRule = Conditional

type Result rule variable =
    Step.Result
        (UnifiedRule (Target variable) (rule (Target variable)))
        (Pattern variable)

type Results rule variable =
    Step.Results
        (UnifiedRule (Target variable) (rule (Target variable)))
        (Pattern variable)

type Renaming variable =
    Map (UnifiedVariable variable) (UnifiedVariable variable)

data InstantiationFailure variable
    = ConcreteFailure (UnifiedVariable variable) (TermLike variable)
    | SymbolicFailure (UnifiedVariable variable) (TermLike variable)
    | UninstantiatedConcrete (UnifiedVariable variable)
    | UninstantiatedSymbolic (UnifiedVariable variable)

instance InternalVariable variable
    => Pretty.Pretty (InstantiationFailure variable)
  where
    pretty (ConcreteFailure var term) =
        Pretty.vsep
            [ "Rule instantiation failure:"
            , Pretty.indent 4 (unparse var <> " is marked as concrete.")
            , Pretty.indent 4
                ("However, " <> unparse term <> " is not concrete.")
            ]
    pretty (SymbolicFailure var term) =
        Pretty.vsep
            [ "Rule instantiation failure:"
            , Pretty.indent 4 (unparse var <> " is marked as symbolic.")
            , Pretty.indent 4
                ("However, " <> unparse term <> " is not symbolic.")
            ]
    pretty (UninstantiatedConcrete var) =
        Pretty.vsep
            [ "Rule instantiation failure:"
            , Pretty.indent 4 (unparse var <> " is marked as concrete.")
            , Pretty.indent 4 "However, it was not instantiated."
            ]
    pretty (UninstantiatedSymbolic var) =
        Pretty.vsep
            [ "Rule instantiation failure:"
            , Pretty.indent 4 (unparse var <> " is marked as symbolic.")
            , Pretty.indent 4 "However, it was not instantiated."
            ]

-- | A rule which can be unified against a configuration
class UnifyingRule rule where
    -- | The pattern used for matching/unifying the rule with the configuration.
    matchingPattern :: rule variable -> TermLike variable

    -- | The condition to be checked upon matching the rule
    precondition :: rule variable -> Predicate variable

    {-| Refresh the variables of a rule.
    The free variables of a rule are implicitly quantified, so they are
    renamed to avoid collision with any variables in the given set.
     -}
    refreshRule
        :: InternalVariable variable
        => FreeVariables variable  -- ^ Variables to avoid
        -> rule variable
        -> (Renaming variable, rule variable)

    {-| Apply a given function to all variables in a rule. This is used for
    distinguishing rule variables from configuration variables.
    -}
    mapRuleVariables
        :: (Ord variable1, FreshPartialOrd variable2, SortedVariable variable2)
        => (ElementVariable variable1 -> ElementVariable variable2)
        -> (SetVariable variable1 -> SetVariable variable2)
        -> rule variable1
        -> rule variable2

    -- | Checks whether a given substitution is acceptable for a rule
    checkInstantiation
        :: InternalVariable variable
        => rule variable
        -> Map.Map (UnifiedVariable variable) (TermLike variable)
        -> [InstantiationFailure variable]
    checkInstantiation _ _ = []
    {-# INLINE checkInstantiation #-}


-- |Unifies/matches a list a rules against a configuration. See 'unifyRule'.
unifyRules
    :: InternalVariable variable
    => MonadSimplify simplifier
    => UnifyingRule rule
    => UnificationProcedure simplifier
    -> SideCondition (Target variable)
    -> Pattern (Target variable)
    -- ^ Initial configuration
    -> [rule (Target variable)]
    -- ^ Rule
    -> simplifier [UnifiedRule (Target variable) (rule (Target variable))]
unifyRules unificationProcedure sideCondition initial rules =
    Branch.gather $ do
        rule <- Branch.scatter rules
        unifyRule unificationProcedure sideCondition initial rule

{- | Attempt to unify a rule with the initial configuration.

The rule variables are renamed to avoid collision with the configuration. The
rule's 'RulePattern.requires' clause is combined with the unification
solution. The combined condition is simplified and checked for
satisfiability.

If any of these steps produces an error, then @unifyRule@ returns that error.

@unifyRule@ returns the renamed rule wrapped with the combined conditions on
unification. The substitution is not applied to the renamed rule.

 -}
unifyRule
    :: InternalVariable variable
    => MonadSimplify simplifier
    => UnifyingRule rule
    => UnificationProcedure simplifier
    -> SideCondition variable
    -- ^ Top level condition.
    -> Pattern variable
    -- ^ Initial configuration
    -> rule variable
    -- ^ Rule
    -> BranchT simplifier (UnifiedRule variable (rule variable))
unifyRule unificationProcedure sideCondition initial rule = do
    let (initialTerm, initialCondition) = Pattern.splitTerm initial
        mergedSideCondition =
            sideCondition `SideCondition.andCondition` initialCondition
    -- Unify the left-hand side of the rule with the term of the initial
    -- configuration.
    let ruleLeft = matchingPattern rule
    unification <-
        unifyTermLikes mergedSideCondition initialTerm ruleLeft
    -- Combine the unification solution with the rule's requirement clause,
    let ruleRequires = precondition rule
        requires' = Condition.fromPredicate ruleRequires
    unification' <-
        simplifyPredicate mergedSideCondition Nothing (unification <> requires')
    return (rule `Conditional.withCondition` unification')
  where
    unifyTermLikes = runUnificationProcedure unificationProcedure

{- | The 'Set' of variables that would be introduced by narrowing.
 -}
-- TODO (thomas.tuegel): Unit tests
wouldNarrowWith
    :: Ord variable
    => UnifyingRule rule
    => UnifiedRule variable (rule variable)
    -> Set (UnifiedVariable variable)
wouldNarrowWith unified =
    Set.difference leftAxiomVariables substitutionVariables
  where
    leftAxiomVariables =
        FreeVariables.getFreeVariables $ TermLike.freeVariables leftAxiom
      where
        Conditional { term = axiom } = unified
        leftAxiom = matchingPattern axiom
    Conditional { substitution } = unified
    substitutionVariables = Map.keysSet (Substitution.toMap substitution)

{- | Prepare a rule for unification or matching with the configuration.

The rule's variables are:

* marked with 'Target' so that they are preferred targets for substitution, and
* renamed to avoid any free variables from the configuration and side condition.

 -}
targetRuleVariables
    :: InternalVariable variable
    => UnifyingRule rule
    => SideCondition (Target variable)
    -> Pattern (Target variable)
    -> rule variable
    -> rule (Target variable)
targetRuleVariables sideCondition initial =
    snd
    . refreshRule avoiding
    . mapRuleVariables Target.mkElementTarget Target.mkSetTarget
  where
    avoiding = freeVariables sideCondition <> freeVariables initial

{- | Unwrap the variables in a 'RulePattern'. Inverse of 'targetRuleVariables'.
 -}
unTargetRule
    :: (FreshPartialOrd variable, SortedVariable variable)
    => UnifyingRule rule
    => rule (Target variable) -> rule variable
unTargetRule = mapRuleVariables Target.unTargetElement Target.unTargetSet

-- |Errors if configuration or matching pattern are not function-like
assertFunctionLikeResults
    :: InternalVariable variable
    => InternalVariable variable'
    => Monad m
    => UnifyingRule rule
    => Eq (rule (Target variable'))
    => TermLike variable
    -> Results rule variable'
    -> m ()
assertFunctionLikeResults termLike results =
    let appliedRules = Result.appliedRule <$> Results.results results
    in case checkFunctionLike appliedRules termLike of
        Left err -> error err
        _        -> return ()

-- |Checks whether configuration and matching pattern are function-like
checkFunctionLike
    :: InternalVariable variable
    => InternalVariable variable'
    => Foldable f
    => UnifyingRule rule
    => Eq (f (UnifiedRule variable' (rule variable')))
    => Monoid (f (UnifiedRule variable' (rule variable')))
    => f (UnifiedRule variable' (rule variable'))
    -> TermLike variable
    -> Either String ()
checkFunctionLike unifiedRules pat
  | unifiedRules == mempty = pure ()
  | TermLike.isFunctionPattern pat =
    Foldable.traverse_ checkFunctionLikeRule unifiedRules
  | otherwise = Left . show . Pretty.vsep $
    [ "Expected function-like term, but found:"
    , Pretty.indent 4 (unparse pat)
    ]
  where
    checkFunctionLikeRule Conditional { term }
      | TermLike.isFunctionPattern left = return ()
      | otherwise = Left . show . Pretty.vsep $
        [ "Expected function-like left-hand side of rule, but found:"
        , Pretty.indent 4 (unparse left)
        ]
      where
        left = matchingPattern term

{- | Apply the initial conditions to the results of rule unification.

The rule is considered to apply if the result is not @\\bottom@.

 -}
applyInitialConditions
    :: forall simplifier variable
    .  InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -- ^ Top-level conditions
    -> Maybe (Condition variable)
    -- ^ Initial conditions
    -> Condition variable
    -- ^ Unification conditions
    -> BranchT simplifier (OrCondition variable)
    -- TODO(virgil): This should take advantage of the BranchT and not return
    -- an OrCondition.
applyInitialConditions sideCondition initial unification = do
    -- Combine the initial conditions and the unification conditions.
    -- The axiom requires clause is included in the unification conditions.
    applied <-
        simplifyPredicate sideCondition initial unification
        & MultiOr.gather
    evaluated <- SMT.Evaluator.filterMultiOr applied
    -- If 'evaluated' is \bottom, the rule is considered to not apply and
    -- no result is returned. If the result is \bottom after this check,
    -- then the rule is considered to apply with a \bottom result.
    TopBottom.guardAgainstBottom evaluated
    return evaluated

-- |Renames configuration variables to distinguish them from those in the rule.
toConfigurationVariables
    :: InternalVariable variable
    => Pattern variable
    -> Pattern (Target variable)
toConfigurationVariables =
    Pattern.mapVariables Target.mkElementNonTarget Target.mkSetNonTarget

-- |Renames configuration variables to distinguish them from those in the rule.
toConfigurationVariablesCondition
    :: InternalVariable variable
    => SideCondition variable
    -> SideCondition (Target variable)
toConfigurationVariablesCondition =
    SideCondition.mapVariables Target.mkElementNonTarget Target.mkSetNonTarget

{- | Apply the remainder predicate to the given initial configuration.

 -}
applyRemainder
    :: forall simplifier variable
    .  InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -- ^ Top level condition
    -> Pattern variable
    -- ^ Initial configuration
    -> Condition variable
    -- ^ Remainder
    -> BranchT simplifier (Pattern variable)
applyRemainder sideCondition initial remainder = do
    let (initialTerm, initialCondition) = Pattern.splitTerm initial
    normalizedCondition <-
        simplifyPredicate sideCondition (Just initialCondition) remainder
    return normalizedCondition { Conditional.term = initialTerm }

-- | Simplifies the predicate obtained upon matching/unification.
simplifyPredicate
    :: forall simplifier variable term
    .  InternalVariable variable
    => MonadSimplify simplifier
    => SideCondition variable
    -> Maybe (Condition variable)
    -> Conditional variable term
    -> BranchT simplifier (Conditional variable term)
simplifyPredicate sideCondition (Just initialCondition) conditional = do
    partialResult <-
        Simplifier.simplifyCondition
            (sideCondition `SideCondition.andCondition` initialCondition)
            conditional
    -- TODO (virgil): Consider using different simplifyPredicate implementations
    -- for rewrite rules and equational rules.
    -- Right now this double simplification both allows using the same code for
    -- both kinds of rules, and allows using the strongest background condition
    -- for simplifying the `conditional`. However, it's not obvious that
    -- using the strongest background condition actually helps in our
    -- use cases, so we may be able to do something better for equations.
    Simplifier.simplifyCondition
        sideCondition
        ( partialResult
        `Pattern.andCondition` initialCondition
        )
simplifyPredicate sideCondition Nothing conditional =
    Simplifier.simplifyCondition
        sideCondition
        conditional
