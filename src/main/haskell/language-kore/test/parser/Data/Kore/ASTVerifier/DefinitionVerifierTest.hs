module Data.Kore.ASTVerifier.DefinitionVerifierTest
    (definitionVerifierTests) where

import           Test.Tasty                                                      (TestTree,
                                                                                  testGroup)

import           Data.Kore.ASTVerifier.DefinitionVerifierAttributesTest
import           Data.Kore.ASTVerifier.DefinitionVerifierImportsTest
import           Data.Kore.ASTVerifier.DefinitionVerifierMetaObjectTest
import           Data.Kore.ASTVerifier.DefinitionVerifierPatternVerifierTest
import           Data.Kore.ASTVerifier.DefinitionVerifierSortUsageTest
import           Data.Kore.ASTVerifier.DefinitionVerifierUniqueNamesTest
import           Data.Kore.ASTVerifier.DefinitionVerifierUniqueSortVariablesTest

definitionVerifierTests :: TestTree
definitionVerifierTests =
    testGroup
        "Definition verifier unit tests"
        [ definitionVerifierUniqueNamesTests
        , definitionVerifierUniqueSortVariablesTests
        , definitionVerifierSortUsageTests
        , definitionVerifierPatternVerifierTests
        , definitionVerifierAttributesTests
        , definitionVerifierImportsTests
        , definitionVerifierMetaObjectTests
        ]
