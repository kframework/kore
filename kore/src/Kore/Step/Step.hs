{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

Direct interface to rule application (step-wise execution).
See "Kore.Step" for the high-level strategy-based interface.

 -}

module Kore.Step.Step
    ( RulePattern
    , UnificationProcedure (..)
    , UnifiedRule
    , Results (..)
    , Result (..)
    , unifyRule
    , unwrapRule
    , applyUnifiedRule
    , applyRule
    , applyRules
    , applyRewriteRule
    , applyRewriteRules
    , sequenceRules
    , sequenceRewriteRules
    , toConfigurationVariables
    , toAxiomVariables
    ) where

import           Control.Applicative
                 ( Alternative (..) )
import           Control.Monad.Except as Monad.Except
import qualified Control.Monad.Morph as Monad.Morph
import qualified Control.Monad.Trans as Monad.Trans
import qualified Data.Foldable as Foldable
import qualified Data.Function as Function
import qualified Data.Map.Strict as Map
import           Data.Semigroup
                 ( Semigroup (..) )
import qualified Data.Set as Set
import qualified Data.Text.Prettyprint.Doc as Pretty
import           GHC.Generics as GHC

import           Kore.AST.Pure
import           Kore.Attribute.Symbol
                 ( StepperAttributes )
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools )
import qualified Kore.Logger as Log
import           Kore.Predicate.Predicate
                 ( Predicate )
import           Kore.Step.Axiom.Data
                 ( BuiltinAndAxiomSimplifierMap )
import           Kore.Step.Error
import           Kore.Step.Pattern as Pattern
import qualified Kore.Step.Remainder as Remainder
import           Kore.Step.Representation.ExpandedPattern
                 ( ExpandedPattern )
import qualified Kore.Step.Representation.ExpandedPattern as ExpandedPattern
import           Kore.Step.Representation.MultiOr
                 ( MultiOr )
import qualified Kore.Step.Representation.MultiOr as MultiOr
import           Kore.Step.Representation.OrOfExpandedPattern
                 ( OrOfPredicateSubstitution )
import           Kore.Step.Representation.Predicated
                 ( Predicated (Predicated) )
import qualified Kore.Step.Representation.Predicated as Predicated
import           Kore.Step.Representation.PredicateSubstitution
                 ( PredicateSubstitution )
import qualified Kore.Step.Representation.PredicateSubstitution as PredicateSubstitution
import           Kore.Step.Rule
                 ( RewriteRule (..), RulePattern (RulePattern) )
import qualified Kore.Step.Rule as Rule
import qualified Kore.Step.Rule as RulePattern
import           Kore.Step.Simplification.Data
import qualified Kore.Step.Substitution as Substitution
import           Kore.Unification.Data
                 ( UnificationProof )
import           Kore.Unification.Error
                 ( UnificationOrSubstitutionError )
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unparser
import           Kore.Variables.Fresh
import           Kore.Variables.Target
                 ( Target )
import qualified Kore.Variables.Target as Target

-- | Wraps functions such as 'unificationProcedure' and
-- 'Kore.Step.Axiom.Matcher.matchAsUnification' to be used in
-- 'stepWithRule'.
newtype UnificationProcedure level =
    UnificationProcedure
        ( forall variable
        .   ( SortedVariable variable
            , Ord (variable level)
            , Show (variable level)
            , Unparse (variable level)
            , OrdMetaOrObject variable
            , ShowMetaOrObject variable
            , MetaOrObject level
            , FreshVariable variable
            )
        => MetadataTools level StepperAttributes
        -> PredicateSubstitutionSimplifier level
        -> StepPatternSimplifier level
        -> BuiltinAndAxiomSimplifierMap level
        -> StepPattern level variable
        -> StepPattern level variable
        -> ExceptT
            (UnificationOrSubstitutionError level variable)
            Simplifier
            ( OrOfPredicateSubstitution level variable
            , UnificationProof level variable
            )
        )

{- | A @UnifiedRule@ has been renamed and unified with a configuration.

The rule's 'RulePattern.requires' clause is combined with the unification
solution and the renamed rule is wrapped with the combined condition.

 -}
type UnifiedRule variable =
    Predicated Object variable (RulePattern Object variable)

-- | The result of applying a single rule.
data Result variable =
    Result
        { unifiedRule :: !(UnifiedRule (Target variable))
        , result      :: !(ExpandedPattern Object variable)
        }
    deriving GHC.Generic

deriving instance Eq (variable Object) => Eq (Result variable)

deriving instance Ord (variable Object) => Ord (Result variable)

deriving instance Show (variable Object) => Show (Result variable)

{- | The results of applying many rules.

The rules may be applied in sequence or in parallel and the 'remainders' vary
accordingly.

 -}
data Results variable =
    Results
        { results :: !(MultiOr (Result variable))
        , remainders :: !(MultiOr (ExpandedPattern Object variable))
        }
    deriving GHC.Generic

deriving instance Eq (variable Object) => Eq (Results variable)

deriving instance Ord (variable Object) => Ord (Results variable)

deriving instance Show (variable Object) => Show (Results variable)

instance Semigroup (Results variable) where
    (<>) results1 results2 =
        Results
            { results = Function.on (<>) results results1 results2
            , remainders = Function.on (<>) remainders results1 results2
            }

instance Monoid (Results variable) where
    mempty = Results { results = empty, remainders = empty }
    mappend = (<>)

withoutRemainders :: Results variable -> Results variable
withoutRemainders results = results { remainders = empty }

unwrapStepErrorVariables
    :: Functor m
    => ExceptT (StepError level (Target variable)) m a
    -> ExceptT (StepError level                  variable ) m a
unwrapStepErrorVariables =
    withExceptT (mapStepErrorVariables Target.unwrapVariable)

{- | Unwrap the variables in a 'RulePattern'.
 -}
unwrapRule
    :: Ord (variable level)
    => RulePattern level (Target variable) -> RulePattern level variable
unwrapRule = Rule.mapVariables Target.unwrapVariable

{- | Remove axiom variables from the substitution and unwrap all variables.
 -}
unwrapConfiguration
    :: Ord (variable level)
    => ExpandedPattern level (Target variable)
    -> ExpandedPattern level variable
unwrapConfiguration config@Predicated { substitution } =
    ExpandedPattern.mapVariables Target.unwrapVariable
        config { ExpandedPattern.substitution = substitution' }
  where
    substitution' = Substitution.filter Target.isNonTarget substitution

wrapUnificationOrSubstitutionError
    :: Functor m
    => ExceptT (UnificationOrSubstitutionError level variable) m a
    -> ExceptT (StepError                      level variable) m a
wrapUnificationOrSubstitutionError =
    withExceptT unificationOrSubstitutionToStepError

{- | Lift an action from the unifier into the stepper.
 -}
liftFromUnification
    :: Monad m
    => BranchT (ExceptT (UnificationOrSubstitutionError level variable) m) a
    -> BranchT (ExceptT (StepError level variable                     ) m) a
liftFromUnification = Monad.Morph.hoist wrapUnificationOrSubstitutionError

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
    ::  forall variable
    .   ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , FreshVariable  variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> UnificationProcedure Object
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -> BuiltinAndAxiomSimplifierMap Object

    -> ExpandedPattern Object variable
    -- ^ Initial configuration
    -> RulePattern Object variable
    -- ^ Rule
    -> BranchT
        (ExceptT (StepError Object variable) Simplifier)
        (UnifiedRule variable)
unifyRule
    metadataTools
    (UnificationProcedure unificationProcedure)
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers

    initial@Predicated { term = initialTerm }
    rule
  = liftFromUnification $ do
    -- Rename free axiom variables to avoid free variables from the initial
    -- configuration.
    let
        configVariables = ExpandedPattern.freeVariables initial
        (_, rule') = RulePattern.refreshRulePattern configVariables rule
    -- Unify the left-hand side of the rule with the term of the initial
    -- configuration.
    let
        RulePattern { left = ruleLeft } = rule'
    unification <- unifyPatterns ruleLeft initialTerm
    -- Combine the unification solution with the rule's requirement clause.
    let
        RulePattern { requires = ruleRequires } = rule'
        requires' = PredicateSubstitution.fromPredicate ruleRequires
    unification' <- normalize (unification <> requires')
    return (rule' `Predicated.withCondition` unification')
  where
    unifyPatterns pat1 pat2 = do
        (unifiers, _) <-
            Monad.Trans.lift
            $ unificationProcedure
                metadataTools
                predicateSimplifier
                patternSimplifier
                axiomSimplifiers
                pat1
                pat2
        scatter unifiers
    normalize condition =
        Substitution.normalizeExcept
            metadataTools
            predicateSimplifier
            patternSimplifier
            axiomSimplifiers
            condition

{- | Apply a rule to produce final configurations given some initial conditions.

The initial conditions are merged with any conditions from the rule unification
and normalized.

 -}
applyUnifiedRule
    ::  forall variable
    .   ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , FreshVariable  variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -> BuiltinAndAxiomSimplifierMap Object

    -> PredicateSubstitution Object variable
    -- ^ Initial conditions
    -> UnifiedRule variable
    -- ^ Non-normalized final configuration
    -> BranchT
        (ExceptT (StepError Object variable) Simplifier)
        (ExpandedPattern Object variable)
applyUnifiedRule
    metadataTools
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers

    initial
    unifiedRule
  = liftFromUnification $ do
    -- Combine the initial conditions, the unification conditions, and the axiom
    -- ensures clause. The axiom requires clause is included by unifyRule.
    let
        Predicated { term = renamedRule } = unifiedRule
        RulePattern { ensures } = renamedRule
        ensuresCondition = PredicateSubstitution.fromPredicate ensures
        unification = Predicated.withoutTerm unifiedRule
    finalCondition <- normalize (initial <> unification <> ensuresCondition)
    -- Apply the normalized substitution to the right-hand side of the axiom.
    let
        Predicated { substitution } = finalCondition
        substitution' = Substitution.toMap substitution
        RulePattern { right = finalTerm } = renamedRule
        finalTerm' = Pattern.substitute substitution' finalTerm
    return finalCondition { ExpandedPattern.term = finalTerm' }
  where
    normalize condition =
        Substitution.normalizeExcept
            metadataTools
            predicateSimplifier
            patternSimplifier
            axiomSimplifiers
            condition

{- | Apply the remainder predicate to the given initial configuration.

 -}
applyRemainder
    ::  forall variable
    .   ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , FreshVariable  variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -> BuiltinAndAxiomSimplifierMap Object

    -> ExpandedPattern Object variable
    -- ^ Initial configuration
    -> Predicate Object variable
    -- ^ Remainder
    -> BranchT
        (ExceptT (StepError Object variable) Simplifier)
        (ExpandedPattern Object variable)
applyRemainder
    metadataTools
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers

    initial
    (PredicateSubstitution.fromPredicate -> remainder)
  = liftFromUnification $ do
    let final = initial `Predicated.andCondition` remainder
        finalCondition = Predicated.withoutTerm final
        Predicated { Predicated.term = finalTerm } = final
    normalizedCondition <- normalize finalCondition
    return normalizedCondition { Predicated.term = finalTerm }
  where
    normalize condition =
        Substitution.normalizeExcept
            metadataTools
            predicateSimplifier
            patternSimplifier
            axiomSimplifiers
            condition

toAxiomVariables
    :: Ord (variable level)
    => RulePattern level variable
    -> RulePattern level (Target variable)
toAxiomVariables = RulePattern.mapVariables Target.Target

toConfigurationVariables
    :: Ord (variable level)
    => ExpandedPattern level variable
    -> ExpandedPattern level (Target variable)
toConfigurationVariables = ExpandedPattern.mapVariables Target.NonTarget

{- | Fully apply a single rule to the initial configuration.

The rule is applied to the initial configuration to produce zero or more final
configurations.

 -}
applyRule
    ::  ( Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        , FreshVariable variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from symbol IDs to defined functions
    -> UnificationProcedure Object

    -> ExpandedPattern Object variable
    -- ^ Configuration being rewritten.
    -> RulePattern Object variable
    -- ^ Rewriting axiom
    -> ExceptT (StepError Object variable) Simplifier
        (MultiOr (Result variable))
applyRule
    metadataTools
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers
    unificationProcedure

    initial
    rule
  = Log.withLogScope "applyRule"
    $ unwrapStepErrorVariables
    $ do
        let
            -- Wrap the rule and configuration so that unification prefers to
            -- substitute axiom variables.
            initial' = toConfigurationVariables initial
            rule' = toAxiomVariables rule
        gather $ do
            unifiedRule <- unifyRule' initial' rule'
            let initialCondition = Predicated.withoutTerm initial'
            final <- applyUnifiedRule' initialCondition unifiedRule
            result <- checkSubstitutionCoverage initial' unifiedRule final
            return Result { unifiedRule, result }
  where
    unifyRule' =
        unifyRule
            metadataTools
            unificationProcedure
            predicateSimplifier
            patternSimplifier
            axiomSimplifiers
    applyUnifiedRule' =
        applyUnifiedRule
            metadataTools
            predicateSimplifier
            patternSimplifier
            axiomSimplifiers

{- | Fully apply a single rewrite rule to the initial configuration.

The rewrite rule is applied to the initial configuration to produce zero or more
final configurations.

 -}
applyRewriteRule
    ::  ( Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        , FreshVariable variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from symbol IDs to defined functions
    -> UnificationProcedure Object

    -> ExpandedPattern Object variable
    -- ^ Configuration being rewritten.
    -> RewriteRule Object variable
    -- ^ Rewriting axiom
    -> ExceptT (StepError Object variable) Simplifier
        (MultiOr (Result variable))
applyRewriteRule
    metadataTools
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers
    unificationProcedure

    initial
    (RewriteRule rule)
  = Log.withLogScope "applyRewriteRule"
    $ applyRule
        metadataTools
        predicateSimplifier
        patternSimplifier
        axiomSimplifiers
        unificationProcedure
        initial
        rule

{- | Check that the final substitution covers the applied rule appropriately.

The final substitution should cover all the free variables on the left-hand side
of the applied rule; otherwise, we would wrongly introduce
universally-quantified variables into the final configuration. Failure of the
coverage check indicates a problem with unification, so in that case
@checkSubstitutionCoverage@ throws an error message with the axiom and the
initial and final configurations.

@checkSubstitutionCoverage@ calls @unwrapVariables@ to remove the axiom
variables from the substitution and unwrap all the 'Target's; this is
safe because we have already checked that all the universally-quantified axiom
variables have been instantiated by the substitution.

 -}
checkSubstitutionCoverage
    ::  ( MetaOrObject level
        , Monad m
        , SortedVariable variable
        , Ord     (variable level)
        , Show    (variable level)
        , Unparse (variable level)
        )
    => ExpandedPattern level (Target variable)
    -- ^ Initial configuration
    -> UnifiedRule (Target variable)
    -- ^ Unified rule
    -> ExpandedPattern level (Target variable)
    -- ^ Configuration after applying rule
    -> BranchT (ExceptT (StepError level (Target variable)) m)
        (ExpandedPattern level variable)
checkSubstitutionCoverage initial unified final
  | isCoveringSubstitution = return (unwrapConfiguration final)
  | isSymbolic =
    -- The substitution does not cover all the variables on the left-hand side
    -- of the rule, but this was not unexpected because the initial
    -- configuration was symbolic. This case is not yet supported, but it is not
    -- a fatal error.
    Monad.Trans.lift (Monad.Except.throwError StepErrorUnsupportedSymbolic)
  | otherwise =
    -- The substitution does not cover all the variables on the left-hand side
    -- of the rule *and* we did not generate a substitution for a symbolic
    -- initial configuration. This is a fatal error because it indicates
    -- something has gone horribly wrong.
    (error . show . Pretty.vsep)
        [ "While applying axiom:"
        , Pretty.indent 4 (Pretty.pretty axiom)
        , "from the initial configuration:"
        , Pretty.indent 4 (unparse initial)
        , "to the final configuration:"
        , Pretty.indent 4 (unparse final)
        , "Failed substitution coverage check!"
        , "Expected substitution (above) to cover all variables:"
        , (Pretty.indent 4 . Pretty.sep)
            (unparse <$> Set.toAscList leftAxiomVariables)
        , "in the left-hand side of the axiom."
        ]
  where
    Predicated { term = axiom } = unified
    leftAxiomVariables =
        Pattern.freeVariables leftAxiom
      where
        RulePattern { left = leftAxiom } = axiom
    Predicated { substitution } = final
    substitutionVariables = Map.keysSet (Substitution.toMap substitution)
    isCoveringSubstitution =
        Set.isSubsetOf leftAxiomVariables substitutionVariables
    isSymbolic =
        Foldable.any Target.isNonTarget substitutionVariables

{- | Apply the given rules to the initial configuration in parallel.

See also: 'applyRewriteRule'

 -}
applyRules
    ::  forall variable
    .   ( Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        , FreshVariable variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from symbol IDs to defined functions
    -> UnificationProcedure Object

    -> [RulePattern Object variable]
    -- ^ Rewrite rules
    -> ExpandedPattern Object variable
    -- ^ Configuration being rewritten
    -> ExceptT (StepError Object variable) Simplifier (Results variable)
applyRules
    metadataTools
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers
    unificationProcedure

    rules
    initial
  = do
    results <- Foldable.fold <$> traverse applyRule' rules
    let unifications = Predicated.withoutTerm . unifiedRule <$> results
    remainders <- gather $ do
        remainder <- scatter (Remainder.remainders unifications)
        applyRemainder' initial remainder
    return Results { results, remainders }
  where
    applyRule' =
        applyRule
            metadataTools
            predicateSimplifier
            patternSimplifier
            axiomSimplifiers
            unificationProcedure
            initial
    applyRemainder' =
        applyRemainder
            metadataTools
            predicateSimplifier
            patternSimplifier
            axiomSimplifiers

{- | Apply the given rewrite rules to the initial configuration in parallel.

See also: 'applyRewriteRule'

 -}
applyRewriteRules
    ::  forall variable
    .   ( Ord (variable Object)
        , Show (variable Object)
        , Unparse (variable Object)
        , FreshVariable variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from symbol IDs to defined functions
    -> UnificationProcedure Object

    -> [RewriteRule Object variable]
    -- ^ Rewrite rules
    -> ExpandedPattern Object variable
    -- ^ Configuration being rewritten
    -> ExceptT (StepError Object variable) Simplifier (Results variable)
applyRewriteRules
    metadataTools
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers
    unificationProcedure

    rewriteRules
  =
    applyRules
        metadataTools
        predicateSimplifier
        patternSimplifier
        axiomSimplifiers
        unificationProcedure
        (getRewriteRule <$> rewriteRules)

{- | Apply the given rewrite rules to the initial configuration in sequence.

See also: 'applyRewriteRule'

 -}
sequenceRules
    ::  forall variable
    .   ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , FreshVariable  variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from symbol IDs to defined functions
    -> UnificationProcedure Object

    -> ExpandedPattern Object variable
    -- ^ Configuration being rewritten
    -> [RulePattern Object variable]
    -- ^ Rewrite rules
    -> ExceptT (StepError Object variable) Simplifier (Results variable)
sequenceRules
    metadataTools
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers
    unificationProcedure
    initialConfig
  =
    Foldable.foldlM sequenceRules1 mempty { remainders = pure initialConfig }
  where
    -- The single remainder of the input configuration after rewriting to
    -- produce the disjunction of results.
    remainingAfter
        :: ExpandedPattern Object variable
        -- ^ initial configuration
        -> MultiOr (Result variable)
        -- ^ disjunction of results
        -> MultiOr (ExpandedPattern Object variable)
    remainingAfter config results =
        let remainder =
                PredicateSubstitution.fromPredicate
                $ Remainder.remainder
                $ Predicated.withoutTerm . unifiedRule <$> results
        in MultiOr.make [config `Predicated.andCondition` remainder]

    sequenceRules1
        :: Results variable
        -> RulePattern Object variable
        -> ExceptT (StepError Object variable) Simplifier (Results variable)
    sequenceRules1 results rule = do
        results' <- traverse (applyRule' rule) (remainders results)
        return (withoutRemainders results <> Foldable.fold results')

    -- Apply rule to produce a pair of the rewritten patterns and
    -- single remainder configuration.
    applyRule' rule config = do
        results <-
            applyRule
                metadataTools
                predicateSimplifier
                patternSimplifier
                axiomSimplifiers
                unificationProcedure
                config
                rule
        return Results
            { results
            , remainders = remainingAfter config results
            }

{- | Apply the given rewrite rules to the initial configuration in sequence.

See also: 'applyRewriteRule'

 -}
sequenceRewriteRules
    ::  forall variable
    .   ( Ord     (variable Object)
        , Show    (variable Object)
        , Unparse (variable Object)
        , FreshVariable  variable
        , SortedVariable variable
        )
    => MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier Object
    -> StepPatternSimplifier Object
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap Object
    -- ^ Map from symbol IDs to defined functions
    -> UnificationProcedure Object

    -> ExpandedPattern Object variable
    -- ^ Configuration being rewritten
    -> [RewriteRule Object variable]
    -- ^ Rewrite rules
    -> ExceptT (StepError Object variable) Simplifier (Results variable)
sequenceRewriteRules
    metadataTools
    predicateSimplifier
    patternSimplifier
    axiomSimplifiers
    unificationProcedure

    initialConfig
    rewriteRules
  =
    sequenceRules
        metadataTools
        predicateSimplifier
        patternSimplifier
        axiomSimplifiers
        unificationProcedure
        initialConfig
        (getRewriteRule <$> rewriteRules)
