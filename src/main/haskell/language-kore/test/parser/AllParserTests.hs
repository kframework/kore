import           Test.Tasty                                          (TestTree,
                                                                      testGroup)

import           Test.Tasty.Runners                                  (consoleTestReporter,
                                                                      defaultMainWithIngredients,
                                                                      listingTests)
import           Test.Tasty.Runners.AntXML                           (antXMLRunner)

import System.Directory (setCurrentDirectory)

import           Data.Kore.Algorithm.TopologicalSortTest
import           Data.Kore.AST.CommonTest
import           Data.Kore.AST.MLPatternsTest
import           Data.Kore.AST.PureToKoreTest
import           Data.Kore.ASTUtils.ASTUtilsTest
import           Data.Kore.ASTHelpersTest
import           Data.Kore.ASTPrettyPrintTest
import           Data.Kore.ASTTraversalsTest
import           Data.Kore.ASTVerifier.ASTVerifierTest
import           Data.Kore.Implicit.ImplicitKoreTest
import           Data.Kore.Implicit.Verified                         (implicitAttributesDefinition,
                                                                      implicitKoreDefinition)
import           Data.Kore.IndentingPrinterTest
import           Data.Kore.IndexedModule.MetadataToolsTest
import           Data.Kore.IndexedModule.ResolversTest
import           Data.Kore.MetaML.LiftUnliftTest
import           Data.Kore.MetaML.UnliftTest
import           Data.Kore.Parser.CharDictTest
import           Data.Kore.Parser.CharSetTest
import           Data.Kore.Parser.CStringTest
import           Data.Kore.Parser.LexemeTest
import           Data.Kore.Parser.ParserTest
import           Data.Kore.Parser.RegressionTest
import           Data.Kore.Step.AxiomPatternsTest
import           Data.Kore.Step.BaseStepTest
import           Data.Kore.Step.Condition.ConditionTest
import           Data.Kore.Step.Condition.EvaluatorTest
import           Data.Kore.Step.Function.IntegrationTest
import           Data.Kore.Step.Function.UserDefinedTest
import           Data.Kore.Step.StepTest
import           Data.Kore.Substitution.ClassTest
import           Data.Kore.Substitution.ListTest
import           Data.Kore.Unification.SubstitutionNormalizationTest
import           Data.Kore.Unification.UnifierTest
import           Data.Kore.Unparser.UnparseTest
import           Data.Kore.Variables.Fresh.IntCounterTest
import           Data.Kore.Variables.IntTest
import           Data.Kore.Variables.SortTest

import qualified Paths

main :: IO ()
main = do
    setCurrentDirectory (Paths.dataFileName ".")
    inputFiles <- regressionTestsInputFiles "../../../test/resources/"
    defaultMainWithIngredients
        [antXMLRunner, listingTests, consoleTestReporter]
        (allParserTests inputFiles)

allParserTests :: [InputFileName] -> TestTree
allParserTests regressionInputFiles =
    testGroup
        " All Parser Tests"
        [ unitTests
        , regressionTests regressionInputFiles
        , implicitKoreRegressionTests
            implicitKoreDefinition
            (InputFileName "../../kore/kore.kore")
            (GoldenFileName "../../../test/expected/kore.kore.golden")
        , implicitKoreRegressionTests
            implicitAttributesDefinition
            (InputFileName "../../kore/attributes.kore")
            (GoldenFileName "../../../test/expected/attributes.kore.golden")
        ]

unitTests :: TestTree
unitTests =
    testGroup
        " Unit Tests"
        [ commonTests
        , astVerifierTests
        , astHelperTests
        , astUtilsTests
        , charDictTests
        , charSetTests
        , cStringTests
        , koreLexemeTests
        , koreParserTests
        , indentingPrinterTests
        , astPrettyPrintTests
        , unparseUnitTests
        , unparseParseTests
        , mlPatternsTests
        , astTraversalsTests
        , variablesFreshIntCounterTests
        , variablesIntTests
        , substitutionListTests
        , substitutionClassTests
        , freeSortVariablesTests
        , liftTests
        , unliftTests
        , unificationTests
        , metadataToolsTests
        , resolversTests
        , pureToKoreTests
        , substitutionNormalizationTests
        , topologicalSortTest
        , baseStepTests
        , stepTests
        , axiomPatternsTests
        , conditionTests
        , conditionEvaluatorTests
        , userDefinedFunctionTests
        , functionIntegrationTests
        ]
