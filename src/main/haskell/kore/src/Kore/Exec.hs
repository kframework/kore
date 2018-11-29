{-|
Module      : Kore.Exec
Description : Expose concrete execution as a library
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Stability   : experimental
Portability : portable

Expose concrete execution as a library
-}
module Kore.Exec
    ( exec
    , search
    , prove
    ) where

import qualified Control.Arrow as Arrow
import           Control.Monad.Trans.Except
                 ( runExceptT )
import qualified Data.Map.Merge.Strict as Map
import qualified Data.Map.Strict as Map
import           Data.Reflection
                 ( give )
import           Data.These
                 ( These (..) )

import           Data.Limit
                 ( Limit (..) )
import qualified Data.Limit as Limit
import           Kore.AST.Common
import           Kore.AST.MetaOrObject
                 ( Meta, Object (..), asUnified )
import qualified Kore.ASTUtils.SmartConstructors as Pattern
import qualified Kore.Builtin as Builtin
import           Kore.IndexedModule.IndexedModule
                 ( KoreIndexedModule )
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools (..), extractMetadataTools )
import           Kore.OnePath.Verification
                 ( Axiom (Axiom), Claim (Claim), defaultStrategy, verify )
import           Kore.Predicate.Predicate
                 ( pattern PredicateTrue, makeMultipleOrPredicate,
                 makeTruePredicate, unwrapPredicate )
import           Kore.Step.AxiomPatterns
                 ( EqualityRule (EqualityRule), RewriteRule (RewriteRule),
                 RulePattern (RulePattern), extractRewriteAxioms,
                 extractRewriteClaims )
import           Kore.Step.AxiomPatterns as RulePattern
                 ( RulePattern (..) )
import           Kore.Step.BaseStep
                 ( StepProof )
import           Kore.Step.ExpandedPattern
                 ( CommonExpandedPattern, Predicated (..), toMLPattern )
import qualified Kore.Step.ExpandedPattern as ExpandedPattern
import qualified Kore.Step.ExpandedPattern as Predicated
import           Kore.Step.Function.Registry
                 ( axiomPatternsToEvaluators, extractFunctionAxioms )
import           Kore.Step.OrOfExpandedPattern
                 ( OrOfExpandedPattern )
import qualified Kore.Step.OrOfExpandedPattern as OrOfExpandedPattern
import           Kore.Step.Pattern
import           Kore.Step.Search
                 ( searchTree )
import qualified Kore.Step.Search as Search
import           Kore.Step.Simplification.Data
                 ( PredicateSubstitutionSimplifier (..),
                 SimplificationProof (..), Simplifier, StepPatternSimplifier )
import qualified Kore.Step.Simplification.ExpandedPattern as ExpandedPattern
import qualified Kore.Step.Simplification.PredicateSubstitution as PredicateSubstitution
import qualified Kore.Step.Simplification.Simplifier as Simplifier
                 ( create )
import           Kore.Step.Step
import           Kore.Step.StepperAttributes
                 ( StepperAttributes (..) )
import           Kore.Step.Strategy
                 ( Tree )
import           Kore.Substitution.Class
                 ( Hashable, substitute )
import qualified Kore.Substitution.List as ListSubstitution
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Variables.Fresh
                 ( FreshVariable )

-- | Concrete execution
exec
    :: KoreIndexedModule StepperAttributes
    -- ^ The main module
    -> CommonStepPattern Object
    -- ^ The input pattern
    -> Limit Natural
    -- ^ The step limit
    -> ([RewriteRule Object] -> Strategy (Prim (RewriteRule Object)))
    -- ^ The strategy to use for execution; see examples in "Kore.Step.Step"
    -> Simplifier (CommonStepPattern Object)
exec indexedModule purePattern stepLimit strategy =
    setUpConcreteExecution indexedModule purePattern stepLimit strategy execute
  where
    execute
        :: MetadataTools Object StepperAttributes
        -> StepPatternSimplifier Object Variable
        -> PredicateSubstitutionSimplifier Object Simplifier
        -> Tree (CommonExpandedPattern Object, StepProof Object Variable)
        -> Simplifier (CommonStepPattern Object)
    execute metadataTools _ _ executionTree =
        give (symbolOrAliasSorts metadataTools) $ do
            let (finalConfig, _) = pickLongest executionTree
            return (ExpandedPattern.toMLPattern finalConfig)

-- | Concrete execution search
search
    :: KoreIndexedModule StepperAttributes
    -- ^ The main module
    -> CommonStepPattern Object
    -- ^ The input pattern
    -> Limit Natural
    -- ^ The step limit
    -> ([RewriteRule Object] -> Strategy (Prim (RewriteRule Object)))
    -- ^ The strategy to use for execution; see examples in "Kore.Step.Step"
    -> CommonExpandedPattern Object
    -- ^ The pattern to match during execution
    -> Search.Config
    -- ^ The bound on the number of search matches and the search type
    -> Simplifier (CommonStepPattern Object)
search
    indexedModule
    purePattern
    stepLimit
    strategy
    searchPattern
    searchConfig
  =
    setUpConcreteExecution indexedModule purePattern stepLimit strategy execute
  where
    execute metadataTools simplifier substitutionSimplifier executionTree = do
        let
            match target (config, _proof) =
                Search.matchWith
                    metadataTools
                    substitutionSimplifier
                    simplifier
                    target
                    config
        solutions <- searchTree searchConfig (match searchPattern) executionTree
        let
            orPredicate =
                give (symbolOrAliasSorts metadataTools)
                $ makeMultipleOrPredicate
                $ fmap Predicated.toPredicate solutions
        return (unwrapPredicate orPredicate)

-- | Provide a MetadataTools, simplifier, subsitution simplifier, and execution
-- tree to the callback.
setUpConcreteExecution
    :: KoreIndexedModule StepperAttributes
    -- ^ The main module
    -> CommonStepPattern Object
    -- ^ The input pattern
    -> Limit Natural
    -- ^ The step limit
    -> ([RewriteRule Object] -> Strategy (Prim (RewriteRule Object)))
    -- ^ The strategy to use for execution; see examples in "Kore.Step.Step"
    -> (MetadataTools Object StepperAttributes
        -> StepPatternSimplifier Object Variable
        -> PredicateSubstitutionSimplifier Object Simplifier
        -> Tree (CommonExpandedPattern Object, StepProof Object Variable)
        -> Simplifier a)
    -- ^ Callback to do the execution
    -> Simplifier a
setUpConcreteExecution indexedModule purePattern stepLimit strategy execute = do
    let
        metadataTools = extractMetadataTools indexedModule
    axiomsAndSimplifiers <-
        makeAxiomsAndSimplifiers indexedModule metadataTools
    let
        (rewriteAxioms, simplifier, substitutionSimplifier) =
            axiomsAndSimplifiers
        runStrategy' pat =
            runStrategy
                (transitionRule metadataTools substitutionSimplifier simplifier)
                (Limit.replicate stepLimit (strategy rewriteAxioms))
                (pat, mempty)
        expandedPattern = makeExpandedPattern purePattern
    simplifiedPatterns <-
        ExpandedPattern.simplify
            metadataTools substitutionSimplifier simplifier expandedPattern
    let
        initialPattern =
            case OrOfExpandedPattern.extractPatterns (fst simplifiedPatterns) of
                [] -> ExpandedPattern.bottom
                (config : _) -> config
    executionTree <- runStrategy' initialPattern
    execute metadataTools simplifier substitutionSimplifier executionTree

makeExpandedPattern
    :: CommonStepPattern Object
    -> CommonExpandedPattern Object
makeExpandedPattern pat =
    Predicated
        { term = pat
        , predicate = makeTruePredicate
        , substitution = mempty
        }

preSimplify
    ::  (  CommonStepPattern Object
        -> Simplifier
            (OrOfExpandedPattern Object Variable, SimplificationProof Object)
        )
    -> RulePattern Object
    -> Simplifier (RulePattern Object)
preSimplify
    simplifier
    RulePattern
        { left = lhs
        , right = rhs
        , requires
        , attributes = atts
        }
  = do
    (simplifiedOrLhs, _proof) <- simplifier lhs
    let
        [Predicated {term, predicate = PredicateTrue, substitution}] =
            OrOfExpandedPattern.extractPatterns simplifiedOrLhs
        listSubst =
            ListSubstitution.fromList
                (map (Arrow.first asUnified) (Substitution.unwrap substitution))
    newLhs <- substitute term listSubst
    newRhs <- substitute rhs listSubst
    newRequires <- traverse (`substitute` listSubst) requires
    return RulePattern
        { left = newLhs
        , right = newRhs
        , requires = newRequires
        , attributes = atts
        }

makeAxiomsAndSimplifiers
    :: KoreIndexedModule StepperAttributes
    -> MetadataTools Object StepperAttributes
    -> Simplifier
        ( [RewriteRule Object]
        , StepPatternSimplifier Object Variable
        , PredicateSubstitutionSimplifier Object Simplifier
        )
makeAxiomsAndSimplifiers indexedModule tools =
    do
        functionAxioms <-
            simplifyFunctionAxioms tools
                (extractFunctionAxioms Object indexedModule)
        rewriteAxioms <-
            simplifyRewriteAxioms tools
                (extractRewriteAxioms Object indexedModule)
        let
            functionEvaluators =
                axiomPatternsToEvaluators functionAxioms
            functionRegistry =
                Map.merge
                    (Map.mapMissing (const This))
                    (Map.mapMissing (const That))
                    (Map.zipWithMatched (const These))
                    -- builtin functions
                    (Builtin.koreEvaluators indexedModule)
                    -- user-defined functions
                    functionEvaluators
            simplifier
                ::  ( SortedVariable variable
                    , Ord (variable Meta)
                    , Ord (variable Object)
                    , Show (variable Meta)
                    , Show (variable Object)
                    , FreshVariable variable
                    , Hashable variable
                    )
                => StepPatternSimplifier Object variable
            simplifier = Simplifier.create tools functionRegistry
            substitutionSimplifier
                :: PredicateSubstitutionSimplifier Object Simplifier
            substitutionSimplifier =
                PredicateSubstitution.create tools simplifier
        return (rewriteAxioms, simplifier, substitutionSimplifier)

simplifyFunctionAxioms
    :: MetadataTools Object StepperAttributes
    -> Map.Map (Id Object) [EqualityRule Object]
    -> Simplifier (Map.Map (Id Object) [EqualityRule Object])
simplifyFunctionAxioms tools = mapM (mapM simplifyEqualityRule)
  where
    simplifyEqualityRule (EqualityRule rule) =
        EqualityRule <$> preSimplify (emptyPatternSimplifier tools) rule

simplifyRewriteAxioms
    :: MetadataTools Object StepperAttributes
    -> [RewriteRule Object]
    -> Simplifier [RewriteRule Object]
simplifyRewriteAxioms tools = mapM simplifyRewriteRule
  where
    simplifyRewriteRule (RewriteRule rule) =
        RewriteRule <$> preSimplify (emptyPatternSimplifier tools) rule

emptyPatternSimplifier
    :: MetadataTools Object StepperAttributes
    -> CommonStepPattern Object
    -> Simplifier
        (OrOfExpandedPattern Object Variable, SimplificationProof Object)
emptyPatternSimplifier tools =
    ExpandedPattern.simplify
        tools
        emptySubstitutionSimplifier
        emptySimplifier
    . makeExpandedPattern
  where
    emptySimplifier
        ::  ( SortedVariable variable
            , Ord (variable Meta)
            , Ord (variable Object)
            , Show (variable Meta)
            , Show (variable Object)
            , FreshVariable variable
            , Hashable variable
            )
        => StepPatternSimplifier Object variable
    emptySimplifier = Simplifier.create tools Map.empty
    emptySubstitutionSimplifier =
        PredicateSubstitution.create tools emptySimplifier


-- | Proving a spec given as a module containing rules to be proven
prove
    :: KoreIndexedModule StepperAttributes
    -- ^ The main module
    -> KoreIndexedModule StepperAttributes
    -- ^ The spec module
    -> Simplifier (CommonStepPattern Object)
prove definitionModule specModule = do
    let
        tools = extractMetadataTools definitionModule
        symbolOrAlias = symbolOrAliasSorts tools
    axiomsAndSimplifiers <-
        makeAxiomsAndSimplifiers definitionModule tools
    let
        (rewriteAxioms, simplifier, substitutionSimplifier) =
            axiomsAndSimplifiers
    specAxioms <-
        simplifyRewriteAxioms tools
            (extractRewriteClaims Object specModule)
    let
        axioms = fmap Axiom rewriteAxioms
        claims = fmap Claim specAxioms

    result <- runExceptT
        $ verify
            tools
            simplifier
            substitutionSimplifier
            (defaultStrategy claims axioms)
            (fmap makeClaim claims)

    return $
        either
            (give symbolOrAlias toMLPattern)
            (const Pattern.mkBottom)
            result

  where
    makeClaim claim = (claim, Unlimited)

