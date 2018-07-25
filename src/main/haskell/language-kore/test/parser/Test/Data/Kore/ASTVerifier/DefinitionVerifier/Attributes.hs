module Test.Data.Kore.ASTVerifier.DefinitionVerifier.Attributes (test_attributes) where

import           Test.Tasty                                    (TestTree)

import           Test.Data.AstGen
import           Test.Data.Kore.ASTVerifier.DefinitionVerifier

import           Data.Kore.AST.Common
import           Data.Kore.AST.Kore
import           Data.Kore.AST.MetaOrObject
import           Data.Kore.AST.PureToKore                      (patternPureToKore)
import           Data.Kore.AST.Sentence
import           Data.Kore.ASTUtils.SmartPatterns
import           Data.Kore.Error
import           Data.Kore.Implicit.Attributes                 (attributeKeyObjectSort,
                                                                attributeObjectSort,
                                                                keyValueAttribute)

test_attributes :: [TestTree]
test_attributes =
    [ expectSuccess "Attribute sorts and symbols visible in attributes"
        Definition
            { definitionAttributes = Attributes
                [ keyValueAttribute "strict" "2" ]
            , definitionModules = []
            }
    , expectFailureWithError "Attribute symbol not visible outside attributes"
        (Error
            [ "module 'M1'"
            , "axiom declaration"
            , "symbol or alias 'keyValueAttribute' (<implicitly defined entity>)"
            , "(<implicitly defined entity>)"
            ]
            "Symbol 'keyValueAttribute' not defined."
        )
        Definition
            { definitionAttributes = Attributes []
            , definitionModules =
                [ Module
                    { moduleName = ModuleName "M1"
                    , moduleSentences = [
                        asSentence
                            (SentenceAxiom
                                { sentenceAxiomParameters = []
                                , sentenceAxiomPattern =
                                    keyValueAttribute "strict" "2"
                                , sentenceAxiomAttributes = Attributes []
                                }::KoreSentenceAxiom
                            )
                    ]
                    , moduleAttributes = Attributes []
                    }
                ]
            }
    , expectFailureWithError "Non-attribute sort not visible in attributes"
        (Error
            [ "module 'M1'"
            , "axiom declaration"
            , "attributes"
            , "\\equals (<test data>)"
            , "sort 'mySort' (<test data>)"
            , "(<test data>)"
            ]
            "Sort 'mySort' not declared."
        )
        Definition
            { definitionAttributes = Attributes []
            , definitionModules =
                [ Module
                    { moduleName = ModuleName "M1"
                    , moduleSentences =
                        [ asSentence
                            (SentenceAxiom
                                { sentenceAxiomParameters = []
                                , sentenceAxiomPattern =
                                    domainValuePattern mySortName
                                , sentenceAxiomAttributes = Attributes
                                    [ sortSwitchingEquals
                                        (OperandSort
                                            (attributeObjectSort
                                                AstLocationTest))
                                        (ResultSort (simpleSort mySortName))
                                        (domainValuePattern mySortName)
                                    ]
                                }::KoreSentenceAxiom
                            )
                        , asSentence
                            (SentenceSort
                                { sentenceSortName = testId "mySort"
                                , sentenceSortParameters = []
                                , sentenceSortAttributes = Attributes []
                                }::KoreSentenceSort Object
                            )
                        ]
                    , moduleAttributes = Attributes []
                    }
                ]
            }
    , expectFailureWithError
        "Attribute sort not visible outside attributes"
        (Error
            [ "module 'M1'"
            , "axiom declaration"
            , "\\dv (<unknown location>)"
            , "sort 'AttributeKey' (<test data>)"
            , "(<test data>)"
            ]
            "Sort 'AttributeKey' not declared."
        )
        Definition
            { definitionAttributes = Attributes []
            , definitionModules =
                [ Module
                    { moduleName = ModuleName "M1"
                    , moduleSentences =
                        [ asSentence
                            (SentenceAxiom
                                { sentenceAxiomParameters = []
                                , sentenceAxiomPattern = patternPureToKore
                                    (DV_ (attributeKeyObjectSort AstLocationTest)
                                        (StringLiteral_ "strict"))
                                , sentenceAxiomAttributes = Attributes []
                                }::KoreSentenceAxiom
                            )
                        , asSentence
                            (SentenceSort
                                { sentenceSortName = testId "mySort"
                                , sentenceSortParameters = []
                                , sentenceSortAttributes = Attributes []
                                }::KoreSentenceSort Object
                            )
                        ]
                    , moduleAttributes = Attributes []
                    }
                ]
            }
    ]
  where
    mySortName :: SortName
    mySortName = SortName "mySort"
    domainValuePattern :: SortName -> CommonKorePattern
    domainValuePattern sortName = patternPureToKore
        (DV_ (simpleSort sortName) (StringLiteral_ "asgn"))
    sortSwitchingEquals
        :: OperandSort Object
        -> ResultSort Object
        -> CommonKorePattern
        -> CommonKorePattern
    sortSwitchingEquals
        (OperandSort operandSort) (ResultSort resultSort) child
      =
        asKorePattern
            (EqualsPattern Equals
                { equalsOperandSort = operandSort
                , equalsResultSort = resultSort
                , equalsFirst = child
                , equalsSecond = child
                }
            )
