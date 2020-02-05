module Test.Kore.Attribute.Overload
    ( test_Overload
    , test_Attributes
    , test_duplicate
    , test_arguments
    , test_parameters
    , test_dont_ignore
    ) where

import Prelude.Kore

import Test.Tasty
import Test.Tasty.HUnit

import qualified Data.Default as Default
import qualified Data.Map.Strict as Map

import Kore.ASTVerifier.DefinitionVerifier
import Kore.Attribute.Overload
import qualified Kore.Builtin as Builtin
import Kore.Error
import Kore.Internal.Symbol
    ( applicationSorts
    , functional
    , injective
    , toSymbolOrAlias
    )
import Kore.Internal.TermLike
import qualified Kore.Step.Axiom.Identifier as AxiomIdentifier
import Kore.Step.Axiom.Registry
import Kore.Syntax.Definition hiding
    ( Alias
    , Symbol
    )

import Test.Kore
import Test.Kore.Attribute.Parser
import Test.Kore.Builtin.Definition
    ( sortDecl
    , symbolDecl
    )
import qualified Test.Kore.Step.MockSymbols as Mock

parseOverload :: Attributes -> Parser (Overload SymbolOrAlias)
parseOverload = parseAttributes

superId :: Id
superId = testId "super"

superSymbol :: Symbol
superSymbol =
    Symbol
        { symbolConstructor = superId
        , symbolParams = []
        , symbolAttributes = Default.def
        , symbolSorts = applicationSorts [] Mock.testSort
        }
    & functional & injective

superSymbolOrAlias :: SymbolOrAlias
superSymbolOrAlias = toSymbolOrAlias superSymbol

subId :: Id
subId = testId "sub"

subSymbol :: Symbol
subSymbol =
    Symbol
        { symbolConstructor = subId
        , symbolParams = []
        , symbolAttributes = Default.def
        , symbolSorts = applicationSorts [] Mock.testSort
        }

subSymbolOrAlias :: SymbolOrAlias
subSymbolOrAlias = toSymbolOrAlias subSymbol

test_Overload :: TestTree
test_Overload =
    testCase "[overload{}(super{}(), sub{}())] :: Overload"
    $ expectSuccess expected $ parseOverload attributes
  where
    expected =
        Overload { getOverload = Just (superSymbolOrAlias, subSymbolOrAlias) }

attribute :: AttributePattern
attribute = overloadAttribute superSymbolOrAlias subSymbolOrAlias

attributes :: Attributes
attributes = Attributes [ attribute ]

test_Attributes :: TestTree
test_Attributes =
    testCase "[overload{}(super{}(), sub{}())] :: Attributes"
    $ expectSuccess attributes $ parseAttributes attributes

test_duplicate :: TestTree
test_duplicate =
    testCase "[overload{}(_, _), overload{}(_, _)]"
    $ expectFailure
    $ parseOverload
    $ Attributes [ attribute, attribute ]

test_arguments :: TestTree
test_arguments =
    testCase "[overload{}(\"illegal\")]"
    $ expectFailure
    $ parseOverload $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        attributePattern overloadSymbol [ attributeString "illegal" ]

test_parameters :: TestTree
test_parameters =
    testCase "[overload{illegal}()]"
    $ expectFailure
    $ parseOverload $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        attributePattern_
            overloadSymbol
                { symbolOrAliasParams =
                    [ SortVariableSort (SortVariable "illegal") ]
                }

test_dont_ignore :: TestTree
test_dont_ignore =
    testCase "Don't ignore overloaded production axioms" $
        case Map.lookup (AxiomIdentifier.Application superId) evaluators of
            Nothing ->
                assertFailure "Should not ignore overloaded production axiom"
            Just _ -> return ()
  where
    evaluators =
        axiomPatternsToEvaluators $ extractEqualityAxioms indexedModule
    verifiedModules =
        assertRight
        $ verifyAndIndexDefinition Builtin.koreVerifiers testDefinition
    indexedModule =
        fromMaybe (error $ "Missing module: " ++ show testModuleName)
        $ Map.lookup testModuleName verifiedModules

    testDefinition =
        Definition
            { definitionAttributes = Attributes []
            , definitionModules = [ testModule ]
            }

    testModuleName = ModuleName "test"
    testModule =
        Module
            { moduleName = testModuleName
            , moduleAttributes = Attributes []
            , moduleSentences =
                [ sortDecl   Mock.testSort
                , symbolDecl superSymbol
                , symbolDecl subSymbol
                , overloadAxiom
                ]
            }

    overloadAxiom :: ParsedSentence
    overloadAxiom =
        SentenceAxiomSentence SentenceAxiom
            { sentenceAxiomParameters = [ sortVarS ]
            , sentenceAxiomAttributes = attributes
            , sentenceAxiomPattern =
                Builtin.externalize
                $ mkEquals sortS
                    (mkApplySymbol superSymbol [])
                    (mkApplySymbol subSymbol   [])
            }
      where
        sortVarS = SortVariable "S"
        sortS = SortVariableSort sortVarS
