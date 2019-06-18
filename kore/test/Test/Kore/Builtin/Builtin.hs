module Test.Kore.Builtin.Builtin
    ( mkPair
    , hpropUnparse
    , testMetadataTools
    , testEnv
    , testSubstitutionSimplifier
    , testTermLikeSimplifier
    , testEvaluators
    , testSymbolWithSolver
    , evaluate
    , evaluateT
    , evaluateToList
    , indexedModule
    , runStep
    , runSMT
    ) where

import qualified Hedgehog
import           Test.Tasty
                 ( TestTree )
import           Test.Tasty.HUnit
                 ( assertEqual, testCase )

import qualified Control.Monad.Trans as Trans
import           Data.Function
                 ( (&) )
import           Data.Map
                 ( Map )
import qualified Data.Map as Map
import           Data.Proxy
import           GHC.Stack
                 ( HasCallStack )

import           Kore.ASTVerifier.DefinitionVerifier
import           Kore.ASTVerifier.Error
                 ( VerifyError )
import qualified Kore.Attribute.Axiom as Attribute
import qualified Kore.Attribute.Null as Attribute
import           Kore.Attribute.Symbol as Attribute
import qualified Kore.Builtin as Builtin
import qualified Kore.Error
import           Kore.IndexedModule.IndexedModule as IndexedModule
import           Kore.IndexedModule.MetadataTools
                 ( SmtMetadataTools )
import qualified Kore.IndexedModule.MetadataToolsBuilder as MetadataTools
                 ( build )
import qualified Kore.Internal.MultiOr as MultiOr
                 ( extractPatterns )
import           Kore.Internal.OrPattern
                 ( OrPattern )
import           Kore.Internal.Pattern
                 ( Pattern )
import qualified Kore.Internal.Symbol as Internal
import           Kore.Internal.TermLike
import           Kore.Parser
                 ( parseKorePattern )
import qualified Kore.Step.Result as Result
                 ( mergeResults )
import           Kore.Step.Rule
                 ( RewriteRule )
import           Kore.Step.Simplification.Data
import qualified Kore.Step.Simplification.Predicate as Simplifier.Predicate
import qualified Kore.Step.Simplification.Simplifier as Simplifier
import qualified Kore.Step.Simplification.TermLike as TermLike
import qualified Kore.Step.Step as Step
import           Kore.Syntax.Definition
                 ( ModuleName, ParsedDefinition )
import           Kore.Unification.Error
                 ( UnificationOrSubstitutionError )
import qualified Kore.Unification.Procedure as Unification
import qualified Kore.Unification.Unify as Monad.Unify
import           Kore.Unparser
                 ( unparseToString )
import           SMT
                 ( SMT )
import qualified SMT

import Test.Kore
import Test.Kore.Builtin.Definition

mkPair
    :: Sort
    -> Sort
    -> TermLike Variable
    -> TermLike Variable
    -> TermLike Variable
mkPair lSort rSort l r =
    mkApplySymbol (pairSort lSort rSort) (pairSymbol lSort rSort) [l, r]

-- | 'testSymbol' is useful for writing unit tests for symbols.
testSymbolWithSolver
    ::  ( HasCallStack
        , p ~ TermLike Variable
        , expanded ~ Pattern Variable
        )
    => (p -> SMT expanded)
    -- ^ evaluator function for the builtin
    -> String
    -- ^ test name
    -> Sort
    -- ^ symbol result sort
    -> Internal.Symbol
    -- ^ symbol being tested
    -> [p]
    -- ^ arguments for symbol
    -> expanded
    -- ^ expected result
    -> TestTree
testSymbolWithSolver eval title resultSort symbol args expected =
    testCase title $ do
        actual <- runSMT eval'
        assertEqual "" expected actual
  where
    eval' = eval $ mkApplySymbol resultSort symbol args

-- -------------------------------------------------------------
-- * Evaluation

verify
    :: ParsedDefinition
    -> Either
        (Kore.Error.Error VerifyError)
        (Map
            ModuleName (VerifiedModule StepperAttributes Attribute.Axiom)
        )
verify = verifyAndIndexDefinition attrVerify Builtin.koreVerifiers
  where
    attrVerify = defaultAttributesVerification Proxy Proxy

verifiedModules
    :: Map ModuleName (VerifiedModule StepperAttributes Attribute.Axiom)
verifiedModules =
    either (error . Kore.Error.printError) id (verify testDefinition)

verifiedModule :: VerifiedModule StepperAttributes Attribute.Axiom
Just verifiedModule = Map.lookup testModuleName verifiedModules

indexedModule :: KoreIndexedModule Attribute.Symbol Attribute.Null
indexedModule =
    verifiedModule
    & IndexedModule.eraseAxiomAttributes
    & IndexedModule.mapPatterns Builtin.externalizePattern

testMetadataTools :: SmtMetadataTools StepperAttributes
testMetadataTools = MetadataTools.build verifiedModule

testSubstitutionSimplifier :: PredicateSimplifier
testSubstitutionSimplifier = Simplifier.Predicate.create

testEvaluators :: BuiltinAndAxiomSimplifierMap
testEvaluators = Builtin.koreEvaluators verifiedModule

testTermLikeSimplifier :: TermLikeSimplifier
testTermLikeSimplifier = Simplifier.create

testEnv :: Env
testEnv =
    Env
        { metadataTools = testMetadataTools
        , simplifierTermLike = testTermLikeSimplifier
        , simplifierPredicate = testSubstitutionSimplifier
        , simplifierAxioms = testEvaluators
        }

evaluate :: TermLike Variable -> SMT (Pattern Variable)
evaluate = evalSimplifier testEnv . TermLike.simplify

evaluateT :: Trans.MonadTrans t => TermLike Variable -> t SMT (Pattern Variable)
evaluateT = Trans.lift . evaluate

evaluateToList :: TermLike Variable -> SMT [Pattern Variable]
evaluateToList =
    fmap MultiOr.extractPatterns
    . evalSimplifier testEnv
    . TermLike.simplifyToOr

runSMT :: SMT a -> IO a
runSMT = SMT.runSMT SMT.defaultConfig emptyLogger

runStep
    :: Pattern Variable
    -- ^ configuration
    -> RewriteRule Variable
    -- ^ axiom
    -> SMT (Either UnificationOrSubstitutionError (OrPattern Variable))
runStep configuration axiom = do
    results <- runStepResult configuration axiom
    return (Step.gatherResults <$> results)

runStepResult
    :: Pattern Variable
    -- ^ configuration
    -> RewriteRule Variable
    -- ^ axiom
    -> SMT (Either UnificationOrSubstitutionError (Step.Results Variable))
runStepResult configuration axiom = do
    results <-
        evalSimplifier testEnv
        $ Monad.Unify.runUnifierT
        $ Step.applyRewriteRulesParallel
            (Step.UnificationProcedure Unification.unificationProcedure)
            [axiom]
            configuration
    return (Result.mergeResults <$> results)

-- | Test unparsing internalized patterns.
hpropUnparse
    :: Hedgehog.Gen (TermLike Variable)
    -- ^ Generate patterns with internal representations
    -> Hedgehog.Property
hpropUnparse gen = Hedgehog.property $ do
    builtin <- Hedgehog.forAll gen
    let syntax = unparseToString builtin
        expected = Builtin.externalizePattern builtin
    Right expected Hedgehog.=== parseKorePattern "<test>" syntax
