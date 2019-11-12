module Test.Kore.Attribute.Symbol.SymbolKywd where

import Test.Tasty
import Test.Tasty.HUnit

import Kore.Attribute.Symbol.SymbolKywd
import Kore.Syntax.Pattern

import Test.Kore.Attribute.Parser

parseSymbolKywd :: Attributes -> Parser SymbolKywd
parseSymbolKywd = parseAttributes

test_symbolKywd :: TestTree
test_symbolKywd =
    testCase "[symbolKywd{}()] :: SymbolKywd"
        $ expectSuccess SymbolKywd { isSymbolKywd = True }
        $ parseSymbolKywd $ Attributes [ symbolKywdAttribute ]

test_Attributes :: TestTree
test_Attributes =
    testCase "[symbolKywd{}()] :: Attributes"
        $ expectSuccess attrs $ parseAttributes attrs
  where
    attrs = Attributes [ symbolKywdAttribute ]

test_duplicate :: TestTree
test_duplicate =
    testCase "[symbolKywd{}(), symbolKywd{}()]"
        $ expectFailure $ parseSymbolKywd
        $ Attributes [ symbolKywdAttribute, symbolKywdAttribute ]

test_arguments :: TestTree
test_arguments =
    testCase "[symbolKywd{}(\"illegal\")]"
        $ expectFailure
        $ parseSymbolKywd $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        attributePattern symbolKywdSymbol [attributeString "illegal"]

test_parameters :: TestTree
test_parameters =
    testCase "[symbolKywd{illegal}()]"
        $ expectFailure
        $ parseSymbolKywd $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        (asAttributePattern . ApplicationF)
            Application
                { applicationSymbolOrAlias =
                    SymbolOrAlias
                        { symbolOrAliasConstructor = symbolKywdId
                        , symbolOrAliasParams =
                            [ SortVariableSort (SortVariable "illegal") ]
                        }
                , applicationChildren = []
                }
