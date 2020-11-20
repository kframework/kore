module Test.Kore.Step.Simplification.IntegrationProperty
    ( test_simplifiesToSimplified
    , test_regressionGeneratedTerms
    ) where

import Prelude.Kore

import Hedgehog
    ( PropertyT
    , annotate
    , discard
    , forAll
    , (===)
    )
import Test.Tasty

import Control.Exception
    ( ErrorCall (..)
    )
import Control.Monad.Catch
    ( MonadThrow
    , catch
    , throwM
    )
import Data.List
    ( isInfixOf
    )
import qualified Data.Map.Strict as Map

import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.SideCondition
    ( SideCondition
    )
import qualified Kore.Internal.SideCondition as SideCondition
    ( top
    )
import qualified Kore.Internal.SideCondition.SideCondition as SideCondition
    ( Representation
    )
import qualified Kore.Internal.SideCondition.SideCondition as SideCondition.Representation
    ( mkRepresentation
    )
import Kore.Internal.TermLike
import Kore.Step.Axiom.EvaluationStrategy
    ( simplifierWithFallback
    )
import qualified Kore.Step.Simplification.Data as Simplification
import qualified Kore.Step.Simplification.Pattern as Pattern
    ( simplify
    )
import Kore.Step.Simplification.Simplify
import qualified SMT

import Kore.Unparser
import Test.ConsistentKore
import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Kore.Step.Simplification
import Test.SMT
    ( testPropertyWithoutSolver
    )
import Test.Tasty.HUnit.Ext

test_simplifiesToSimplified :: TestTree
test_simplifiesToSimplified =
    testPropertyWithoutSolver "simplify returns simplified pattern" $ do
        term <- forAll (runTermGen Mock.generatorSetup termLikeGen)
        (annotate . unlines)
            [" ***** unparsed input =", unparseToString term, " ***** "]
        simplified <- catch
            (evaluateT (Pattern.fromTermLike term))
            (exceptionHandler term)
        (===) True (OrPattern.isSimplified sideRepresentation simplified)
  where
    -- Discard exceptions that are normal for randomly generated patterns.
    exceptionHandler
        :: MonadThrow m
        => TermLike VariableName
        -> ErrorCall
        -> PropertyT m a
    exceptionHandler term err@(ErrorCallWithLocation message _location)
      | "Unification case that should be handled somewhere else"
        `isInfixOf` message
      = discard
      | otherwise = do
        traceM ("Error for input: " ++ unparseToString term)
        throwM err

test_regressionGeneratedTerms :: [TestTree]
test_regressionGeneratedTerms =
    [ testCase "Term simplifier should not crash with not simplified error" $ do
        let term =
                mkFloor Mock.testSort1
                    (mkAnd
                        (mkIff
                            Mock.plain00SubSubsort
                            Mock.aSubSubsort
                        )
                        (mkEquals
                            Mock.subSubsort
                            (mkCeil stringMetaSort
                                (mkCeil Mock.boolSort (mkExists Mock.xSubOtherSort Mock.b))
                            )
                            (mkNu
                                Mock.xStringMetaSort
                                (mkForall
                                    Mock.xSubSort (mkSetVar Mock.xStringMetaSort)
                                )
                            )
                        )
                    )
        simplified <-
            Pattern.simplify
                SideCondition.top
                (Pattern.fromTermLike term)
            & runSimplifier Mock.env
        assertEqual "" True (OrPattern.isSimplified sideRepresentation simplified)
    ]

evaluateT
    :: MonadTrans t
    => Pattern VariableName
    -> t SMT.NoSMT (OrPattern VariableName)
evaluateT = lift . evaluate

evaluate :: Pattern VariableName -> SMT.NoSMT (OrPattern VariableName)
evaluate = evaluateWithAxioms Map.empty

evaluateWithAxioms
    :: BuiltinAndAxiomSimplifierMap
    -> Pattern VariableName
    -> SMT.NoSMT (OrPattern VariableName)
evaluateWithAxioms axioms =
    Simplification.runSimplifier env . Pattern.simplify SideCondition.top
  where
    env = Mock.env { simplifierAxioms }
    simplifierAxioms :: BuiltinAndAxiomSimplifierMap
    simplifierAxioms =
        Map.unionWith
            simplifierWithFallback
            Mock.builtinSimplifiers
            axioms

sideRepresentation :: SideCondition.Representation
sideRepresentation =
    SideCondition.Representation.mkRepresentation
    (SideCondition.top :: SideCondition VariableName)
