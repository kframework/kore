module Test.Kore.Attribute.Simplification where

import Test.Tasty
import Test.Tasty.HUnit

import Kore.AST.Pure
import Kore.Attribute.Simplification

import Test.Kore.Attribute.Parser

parseSimplification :: Attributes -> Parser Simplification
parseSimplification = parseAttributes

test_simplification :: TestTree
test_simplification =
    testCase "[simplification{}()] :: Simplification"
        $ expectSuccess Simplification { isSimplification = True }
        $ parseSimplification $ Attributes [ simplificationAttribute ]

test_Attributes :: TestTree
test_Attributes =
    testCase "[simplification{}()] :: Attributes"
        $ expectSuccess attrs $ parseAttributes attrs
  where
    attrs = Attributes [ simplificationAttribute ]

test_duplicate :: TestTree
test_duplicate =
    testCase "[simplification{}(), simplification{}()]"
        $ expectFailure
        $ parseSimplification
        $ Attributes [ simplificationAttribute, simplificationAttribute ]

test_arguments :: TestTree
test_arguments =
    testCase "[simplification{}(\"illegal\")]"
        $ expectFailure
        $ parseSimplification $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        (asAttributePattern . ApplicationPattern)
            Application
                { applicationSymbolOrAlias = simplificationSymbol
                , applicationChildren =
                    [ (asAttributePattern . StringLiteralPattern)
                        (StringLiteral "illegal")
                    ]
                }

test_parameters :: TestTree
test_parameters =
    testCase "[simplification{illegal}()]"
        $ expectFailure
        $ parseSimplification $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        (asAttributePattern . ApplicationPattern)
            Application
                { applicationSymbolOrAlias =
                    SymbolOrAlias
                        { symbolOrAliasConstructor = simplificationId
                        , symbolOrAliasParams =
                            [ SortVariableSort (SortVariable "illegal") ]
                        }
                , applicationChildren = []
                }
