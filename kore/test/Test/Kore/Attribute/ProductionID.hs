module Test.Kore.Attribute.ProductionID where

import Test.Tasty
import Test.Tasty.HUnit

import Kore.AST.Pure
import Kore.Attribute.ProductionID

import Test.Kore.Attribute.Parser

parseProductionID :: Attributes -> Parser ProductionID
parseProductionID = parseAttributes

test_productionID :: TestTree
test_productionID =
    testCase "[productionID{}(\"string\")] :: ProductionID"
        $ expectSuccess ProductionID { getProductionID = Just "string" }
        $ parseProductionID
        $ Attributes [ productionIDAttribute "string" ]

test_Attributes :: TestTree
test_Attributes =
    testCase "[productionID{}(\"string\")] :: Attributes"
        $ expectSuccess attrs $ parseAttributes attrs
  where
    attrs = Attributes [ productionIDAttribute "string" ]

test_duplicate :: TestTree
test_duplicate =
    testCase "[productionID{}(\"string\"), productionID{}(\"string\")]"
        $ expectFailure
        $ parseProductionID $ Attributes [ attr, attr ]
  where
    attr = productionIDAttribute "string"

test_zeroArguments :: TestTree
test_zeroArguments =
    testCase "[productionID{}()]"
        $ expectFailure
        $ parseProductionID $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        (asAttributePattern . ApplicationPattern)
            Application
                { applicationSymbolOrAlias = productionIDSymbol
                , applicationChildren = []
                }

test_twoArguments :: TestTree
test_twoArguments =
    testCase "[productionID{}()]"
        $ expectFailure
        $ parseProductionID $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        (asAttributePattern . ApplicationPattern)
            Application
                { applicationSymbolOrAlias = productionIDSymbol
                , applicationChildren =
                    [ (asAttributePattern . StringLiteralPattern)
                        (StringLiteral "illegal")
                    , (asAttributePattern . StringLiteralPattern)
                        (StringLiteral "illegal")
                    ]
                }

test_parameters :: TestTree
test_parameters =
    testCase "[productionID{illegal}(\"string\")]"
        $ expectFailure
        $ parseProductionID $ Attributes [ illegalAttribute ]
  where
    illegalAttribute =
        (asAttributePattern . ApplicationPattern)
            Application
                { applicationSymbolOrAlias =
                    SymbolOrAlias
                        { symbolOrAliasConstructor = productionIDId
                        , symbolOrAliasParams =
                            [ SortVariableSort (SortVariable "illegal") ]
                        }
                , applicationChildren =
                    [ (asAttributePattern . StringLiteralPattern)
                        (StringLiteral "string")
                    ]
                }
