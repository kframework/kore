module Test.Kore.Parser.Parser (test_koreParser) where

import Test.Tasty
       ( TestTree, testGroup )

import Data.Text
       ( Text )

import           Kore.AST.Pure
import           Kore.AST.Sentence
import           Kore.AST.Valid
import qualified Kore.Domain.Builtin as Domain
import           Kore.Parser.Parser
import           Kore.Syntax.Sentence

import Test.Kore hiding
       ( sortVariable, sortVariableSort )
import Test.Kore.Parser

test_koreParser :: [TestTree]
test_koreParser =
    [ testGroup "objectSortParser" objectSortParserTests
    , testGroup "metaSortConverter" metaSortConverterTests
    , testGroup "objectSortListParser" objectSortListParserTests
    , testGroup "metaSortListParser" metaSortListParserTests
    , testGroup "objectSortVariableParser" objectSortVariableParserTests
    , testGroup "metaSortVariableParser" metaSortVariableParserTests
    , testGroup
        "objectInCurlyBracesSortVariableListParser"
        objectInCurlyBracesSortVariableListParserTest
    , testGroup
        "metaInCurlyBracesSortVariableListParser"
        metaInCurlyBracesSortVariableListParserTest
    , testGroup "objectAliasParser" objectAliasParserTests
    , testGroup "objectSymbolParser" objectSymbolParserTests
    , testGroup "metaAliasParser" metaAliasParserTests
    , testGroup "metaSymbolParser" metaSymbolParserTests
    , testGroup "variableParser" variableParserTests
    , testGroup "andPatternParser" andPatternParserTests
    , testGroup "applicationPatternParser" applicationPatternParserTests
    , testGroup "bottomPatternParser" bottomPatternParserTests
    , testGroup "ceilPatternParser" ceilPatternParserTests
    , testGroup "domainValuePatternParser" domainValuePatternParserTests
    , testGroup "equalsPatternParser" equalsPatternParserTests
    , testGroup "existsPatternParser" existsPatternParserTests
    , testGroup "floorPatternParser" floorPatternParserTests
    , testGroup "forallPatternParser" forallPatternParserTests
    , testGroup "iffPatternParser" iffPatternParserTests
    , testGroup "impliesPatternParser" impliesPatternParserTests
    , testGroup "memPatternParser" memPatternParserTests
    , testGroup "nextPatternParser" nextPatternParserTests
    , testGroup "notPatternParser" notPatternParserTests
    , testGroup "orPatternParser" orPatternParserTests
    , testGroup "rewritesPatternParser" rewritesPatternParserTests
    , testGroup "stringLiteralPatternParser" stringLiteralPatternParserTests
    , testGroup "topPatternParser" topPatternParserTests
    , testGroup "variablePatternParser" variablePatternParserTests
    , testGroup "sentenceAliasParser" sentenceAliasParserTests
    , testGroup "sentenceImportParser" sentenceImportParserTests
    , testGroup "sentenceAxiomParser" sentenceAxiomParserTests
    , testGroup "sentenceClaimParser" sentenceClaimParserTests
    , testGroup "sentenceSortParser" sentenceSortParserTests
    , testGroup "sentenceSymbolParser" sentenceSymbolParserTests
    , testGroup "attributesParser" attributesParserTests
    , testGroup "sentenceHookedSortParser" sentenceHookedSortParserTests
    , testGroup "sentenceHookedSymbolParser" sentenceHookedSymbolParserTests
    , testGroup "moduleParser" moduleParserTests
    , testGroup "definitionParser" definitionParserTests
    ]

objectSortParserTests :: [TestTree]
objectSortParserTests =
    parseTree sortParser
        [ success "var" $
            SortVariableSort ( SortVariable (testId "var") )
        , success "sort1{}" $
            SortActualSort SortActual
                { sortActualName = testId "sort1"
                , sortActualSorts = []
                }
        , success "sort1{sort2}" $
            SortActualSort SortActual
                { sortActualName = testId "sort1"
                , sortActualSorts =
                    [ SortVariableSort ( SortVariable (testId "sort2") ) ]
                }
        , success "sort1{sort2, sort3}" $
            SortActualSort SortActual
                { sortActualName = testId "sort1"
                , sortActualSorts =
                    [ SortVariableSort ( SortVariable (testId "sort2") )
                    , SortVariableSort ( SortVariable (testId "sort3") )
                    ]
                }
        , success "sort1{sort2{sort3}}" $
            SortActualSort SortActual
                { sortActualName = testId "sort1"
                , sortActualSorts =
                    [ SortActualSort SortActual
                        { sortActualName = testId "sort2"
                        , sortActualSorts =
                            [ SortVariableSort (SortVariable (testId "sort3")) ]
                        }
                    ]
                }
        , FailureWithoutMessage ["var1, var2", "var1{var1 var2}"]
        ]

metaSortConverterTests :: [TestTree]
metaSortConverterTests =
    parseTree sortParser
        [ success "#var"
            (SortVariableSort (SortVariable (testId "#var")))
        , success "#Char{}" charMetaSort
        , success "#String{}" stringMetaSort
        , FailureWithoutMessage
            [ "var1, var2", "var1{var1 var2}"
            ]
        ]

objectSortListParserTests :: [TestTree]
objectSortListParserTests =
    parseTree (inParenthesesListParser sortParser)
        [ success "()" []
        , success "(var)"
            [ sortVariableSort "var" ]
        , success "( var1  , var2   )  "
            [ sortVariableSort "var1"
            , sortVariableSort "var2"
            ]
        , success "(sort1{sort2}, var)"
            [ SortActualSort SortActual
                { sortActualName = testId "sort1"
                , sortActualSorts =
                    [ sortVariableSort "sort2" ]
                }
            , sortVariableSort "var"
            ]
        , FailureWithoutMessage ["(var1 var2)"]
        ]

metaSortListParserTests :: [TestTree]
metaSortListParserTests =
    parseTree (inCurlyBracesListParser sortParser)
        [ success "{}" []
        , success "{#var}"
            [SortVariableSort (SortVariable (testId "#var"))]
        , success "{#var1, #var2}"
            [ SortVariableSort (SortVariable (testId "#var1"))
            , SortVariableSort (SortVariable (testId "#var2"))
            ]
        , success "{#Char{  }  , #var}"
            [ charMetaSort
            , SortVariableSort (SortVariable (testId "#var"))
            ]
        , FailureWithoutMessage
            [ "{#var1 #var2}" ]
        ]

objectSortVariableParserTests :: [TestTree]
objectSortVariableParserTests =
    parseTree sortVariableParser
        [ success "var" (SortVariable (testId "var"))
        , FailureWithoutMessage ["", "#"]
        ]

metaSortVariableParserTests :: [TestTree]
metaSortVariableParserTests =
    parseTree sortVariableParser
        [ success "#var" (SortVariable (testId "#var"))
        , FailureWithoutMessage ["", "#"]
        ]

objectInCurlyBracesSortVariableListParserTest :: [TestTree]
objectInCurlyBracesSortVariableListParserTest =
    parseTree (inCurlyBracesListParser sortVariableParser)
        [ success "{}" []
        , success "{var}"
            [ SortVariable (testId "var") ]
        , success "{var1, var2}"
            [ SortVariable (testId "var1")
            , SortVariable (testId "var2")
            ]
        , FailureWithoutMessage
            [ "{var1 var2}", "{var, Int{}}" ]
        ]

metaInCurlyBracesSortVariableListParserTest :: [TestTree]
metaInCurlyBracesSortVariableListParserTest =
    parseTree (inCurlyBracesListParser sortVariableParser)
        [ success "{}" []
        , success "{#var}"
            [ SortVariable (testId "#var") ]
        , success "{#var1, #var2}"
            [ SortVariable (testId "#var1")
            , SortVariable (testId "#var2")
            ]
        , FailureWithoutMessage
            [ "{#var1 #var2}", "{#var, #Char{}}" ]
        ]

objectAliasParserTests :: [TestTree]
objectAliasParserTests =
    parseTree aliasParser
        [ success "c1{}"
            Alias
                { aliasConstructor = testId "c1"
                , aliasParams = []
                }
        , success "c1{s1}"
            Alias
                { aliasConstructor = testId "c1"
                , aliasParams = [ sortVariable "s1" ]
                }
        , success "c1{s1,s2}"
            Alias
                { aliasConstructor = testId "c1"
                , aliasParams =
                    [ sortVariable "s1"
                    , sortVariable "s2"
                    ]
                }
        , FailureWithoutMessage
            ["alias", "a1{a2},a1{a2}", "a1{a2 a2}", "a1{a2}a1{a2}", "c1{s1{}}"]
        ]

objectSymbolParserTests :: [TestTree]
objectSymbolParserTests =
    parseTree symbolParser
        [ success "c1{}"
            Symbol
                { symbolConstructor = testId "c1"
                , symbolParams = []
                }
        , success "c1{s1}"
            Symbol
                { symbolConstructor = testId "c1"
                , symbolParams = [ sortVariable "s1" ]
                }
        , success "c1{s1,s2}"
            Symbol
                { symbolConstructor = testId "c1"
                , symbolParams =
                    [ sortVariable "s1"
                    , sortVariable "s2"
                    ]
                }
        , FailureWithoutMessage
            ["symbol", "a1{a2},a1{a2}", "a1{a2 a2}", "a1{a2}a1{a2}", "c1{s1{}}"]
        ]

metaAliasParserTests :: [TestTree]
metaAliasParserTests =
    parseTree aliasParser
        [ success "#c1{}"
            Alias
                { aliasConstructor = testId "#c1"
                , aliasParams = []
                }
        , success "#c1{#s1}"
            Alias
                { aliasConstructor = testId "#c1"
                , aliasParams = [sortVariable "#s1"]
                }
        , success "#c1{#s1,#s2}"
            Alias
                { aliasConstructor = testId "#c1"
                , aliasParams =
                    [ sortVariable "#s1"
                    , sortVariable "#s2"
                    ]
                }
        , FailureWithoutMessage
            [ "#alias", "#a1{#a2},#a1{#a2}", "#a1{#a2 #a2}", "#a1{#a2}#a1{#a2}"
            , "#c1{#Char{}}"
            ]
        ]

metaSymbolParserTests :: [TestTree]
metaSymbolParserTests =
    parseTree symbolParser
        [ success "#c1{}"
            Symbol
                { symbolConstructor = testId "#c1"
                , symbolParams = []
                }
        , success "#c1{#s1}"
            Symbol
                { symbolConstructor = testId "#c1"
                , symbolParams = [sortVariable "#s1"]
                }
        , success "#c1{#s1,#s2}"
            Symbol
                { symbolConstructor = testId "#c1"
                , symbolParams =
                    [ sortVariable "#s1"
                    , sortVariable "#s2"
                    ]
                }
        , FailureWithoutMessage
            [ "#symbol", "#a1{#a2},#a1{#a2}", "#a1{#a2 #a2}", "#a1{#a2}#a1{#a2}"
            , "#c1{#Char{}}"
            ]
        ]

variableParserTests :: [TestTree]
variableParserTests =
    parseTree variableParser
        [ success "v:s"
            Variable
                { variableName = testId "v"
                , variableSort = sortVariableSort "s"
                , variableCounter = mempty
                }
        , success "v:s1{s2}"
            Variable
                { variableName = testId "v"
                , variableSort =
                    SortActualSort SortActual
                        { sortActualName = testId "s1"
                        , sortActualSorts = [ sortVariableSort "s2" ]
                        }
                , variableCounter = mempty
                }
        , FailureWithoutMessage ["", "var", "v:", ":s"]
        ]

andPatternParserTests :: [TestTree]
andPatternParserTests =
    parseTree korePatternParser
        [ success "\\and{s}(\"a\", \"b\")"
            ( asParsedPattern $ AndPattern And
                { andSort = sortVariableSort "s" :: Sort
                , andFirst =
                    asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                , andSecond =
                    asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                }
            )
        , FailureWithoutMessage
            [ ""
            , "\\and{s,s}(\"a\", \"b\")"
            , "\\and{}(\"a\", \"b\")"
            , "\\and{s}(\"a\")"
            , "\\and{s}(\"a\", \"b\", \"c\")"
            , "\\and{s}(\"a\" \"b\")"
            ]
        ]
applicationPatternParserTests :: [TestTree]
applicationPatternParserTests =
    parseTree korePatternParser
        [ success "#v:#Char"
            ( asParsedPattern . SetVariablePattern . SetVariable $ Variable
                { variableName = testId "#v"
                , variableSort = sortVariableSort "#Char"
                , variableCounter = mempty
                }
            )
        , success "v:s1{s2}"
            ( asParsedPattern $ VariablePattern Variable
                { variableName = testId "v" :: Id
                , variableSort =
                    SortActualSort SortActual
                        { sortActualName = testId "s1"
                        , sortActualSorts = [ sortVariableSort "s2" ]
                        }
                , variableCounter = mempty
                }
            )
        , success "c{s1,s2}(v1:s1, v2:s2)"
            ( asParsedPattern $ ApplicationPattern Application
                { applicationSymbolOrAlias =
                    SymbolOrAlias
                        { symbolOrAliasConstructor = testId "c" :: Id
                        , symbolOrAliasParams =
                            [ sortVariableSort "s1"
                            , sortVariableSort "s2" ]
                        }
                , applicationChildren =
                    [ asParsedPattern $ VariablePattern Variable
                        { variableName = testId "v1" :: Id
                        , variableSort = sortVariableSort "s1"
                        , variableCounter = mempty
                        }
                    , asParsedPattern $ VariablePattern Variable
                        { variableName = testId "v2" :: Id
                        , variableSort = sortVariableSort "s2"
                        , variableCounter = mempty
                        }
                    ]
                }
            )
        , success "c{}()"
            ( asParsedPattern $ ApplicationPattern Application
                { applicationSymbolOrAlias =
                    SymbolOrAlias
                        { symbolOrAliasConstructor = testId "c" :: Id
                        , symbolOrAliasParams = []
                        }
                , applicationChildren = []
                }
            )
        , FailureWithoutMessage ["", "var", "v:", ":s", "c(s)", "c{s}"]
        ]
bottomPatternParserTests :: [TestTree]
bottomPatternParserTests =
    parseTree korePatternParser
        [ success "\\bottom{#Sort}()"
            (asParsedPattern $ BottomPattern $ Bottom
                (sortVariableSort "#Sort" :: Sort)
            )
        , FailureWithoutMessage
            [ ""
            , "\\bottom()"
            , "\\bottom{}()"
            , "\\bottom{s, s}()"
            , "\\bottom{s}"
            ]
        ]
ceilPatternParserTests :: [TestTree]
ceilPatternParserTests =
    parseTree korePatternParser
        [ success "\\ceil{s1, s2}(\"a\")"
            (asParsedPattern $ CeilPattern Ceil
                    { ceilOperandSort = sortVariableSort "s1" :: Sort
                    , ceilResultSort = sortVariableSort "s2"
                    , ceilChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\ceil{s1, s2}()"
            , "\\ceil{s1}(\"a\")"
            , "\\ceil{s1, s2, s3}(\"a\")"
            , "\\ceil{s1 s2}(\"a\")"
            ]
        ]
domainValuePatternParserTests :: [TestTree]
domainValuePatternParserTests =
    parseTree korePatternParser
        [ success "\\dv{s1}(\"a\")"
            $ eraseAnnotations
            $ mkDomainValue
            $ Domain.BuiltinExternal Domain.External
                { domainValueSort = sortVariableSort "s1"
                , domainValueChild =
                    Kore.AST.Pure.eraseAnnotations
                    $ mkStringLiteral "a"
                }
        , FailureWithoutMessage
            [ ""
            , "\\dv{s1, s2}(\"a\")"
            , "\\dv{}(\"a\")"
            , "\\dv{s1}()"
            ]
        ]
equalsPatternParserTests :: [TestTree]
equalsPatternParserTests =
    parseTree korePatternParser
        [ success "\\equals{s1, s2}(\"a\", \"b\")"
            ( asParsedPattern $ EqualsPattern Equals
                    { equalsOperandSort = sortVariableSort "s1" :: Sort
                    , equalsResultSort = sortVariableSort "s2"
                    , equalsFirst =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    , equalsSecond =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\equals{s}(\"a\", \"b\")"
            , "\\equals{s,s,s}(\"a\", \"b\")"
            , "\\equals{s,s}(\"a\")"
            , "\\equals{s,s}(\"a\", \"b\", \"c\")"
            , "\\equals{s,s}(\"a\" \"b\")"
            ]
        ]
existsPatternParserTests :: [TestTree]
existsPatternParserTests =
    parseTree korePatternParser
        [ success "\\exists{#s}(#v:#Char, \"b\")"
            (asParsedPattern $ ExistsPattern Exists
                    { existsSort = sortVariableSort "#s" :: Sort
                    , existsVariable =
                        Variable
                            { variableName = testId "#v"
                            , variableSort = sortVariableSort "#Char"
                            , variableCounter = mempty
                            }
                    , existsChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\exists{}(v:s1, \"b\")"
            , "\\exists{s,s}(v:s1, \"b\")"
            , "\\exists{s}(\"b\", \"b\")"
            , "\\exists{s}(, \"b\")"
            , "\\exists{s}(\"b\")"
            , "\\exists{s}(v:s1, )"
            , "\\exists{s}(v:s1)"
            , "\\exists{s}()"
            , "\\exists{s}"
            , "\\exists"
            , "\\exists(v:s1, \"b\")"
            ]
        ]
floorPatternParserTests :: [TestTree]
floorPatternParserTests =
    parseTree korePatternParser
        [ success "\\floor{s1, s2}(\"a\")"
            ( asParsedPattern $ FloorPattern Floor
                    { floorOperandSort = sortVariableSort "s1" :: Sort
                    , floorResultSort = sortVariableSort "s2"
                    , floorChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\floor{s1, s2}()"
            , "\\floor{s1}(\"a\")"
            , "\\floor{s1, s2, s3}(\"a\")"
            , "\\floor{s1 s2}(\"a\")"
            ]
        ]
forallPatternParserTests :: [TestTree]
forallPatternParserTests =
    parseTree korePatternParser
        [ success "\\forall{s}(v:s1, \"b\")"
            ( asParsedPattern $ ForallPattern Forall
                    { forallSort = sortVariableSort "s" :: Sort
                    , forallVariable =
                        Variable
                            { variableName = testId "v"
                            , variableSort = sortVariableSort "s1"
                            , variableCounter = mempty
                            }
                    , forallChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\forall{}(v:s1, \"b\")"
            , "\\forall{s,s}(v:s1, \"b\")"
            , "\\forall{s}(\"b\", \"b\")"
            , "\\forall{s}(, \"b\")"
            , "\\forall{s}(\"b\")"
            , "\\forall{s}(v:s1, )"
            , "\\forall{s}(v:s1)"
            , "\\forall{s}()"
            , "\\forall{s}"
            , "\\forall"
            , "\\forall(v:s1, \"b\")"
            ]
        ]
iffPatternParserTests :: [TestTree]
iffPatternParserTests =
    parseTree korePatternParser
        [ success "\\iff{s}(\"a\", \"b\")"
            ( asParsedPattern $ IffPattern Iff
                    { iffSort = sortVariableSort "s" :: Sort
                    , iffFirst =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    , iffSecond =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\iff{s,s}(\"a\", \"b\")"
            , "\\iff{}(\"a\", \"b\")"
            , "\\iff{s}(\"a\")"
            , "\\iff{s}(\"a\", \"b\", \"c\")"
            , "\\iff{s}(\"a\" \"b\")"]
        ]
impliesPatternParserTests :: [TestTree]
impliesPatternParserTests =
    parseTree korePatternParser
        [ success "\\implies{s}(\"a\", \"b\")"
            ( asParsedPattern $ ImpliesPattern Implies
                    { impliesSort = sortVariableSort "s" :: Sort
                    , impliesFirst =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    , impliesSecond =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\implies{s,s}(\"a\", \"b\")"
            , "\\implies{}(\"a\", \"b\")"
            , "\\implies{s}(\"a\")"
            , "\\implies{s}(\"a\", \"b\", \"c\")"
            , "\\implies{s}(\"a\" \"b\")"]
        ]
memPatternParserTests :: [TestTree]
memPatternParserTests =
    parseTree korePatternParser
        [ success "\\in{s1,s2}(v:s3, \"b\")"
            ( asParsedPattern $ InPattern In
                    { inOperandSort = sortVariableSort "s1" :: Sort
                    , inResultSort = sortVariableSort "s2"
                    , inContainedChild = asParsedPattern $
                        VariablePattern Variable
                            { variableName = testId "v" :: Id
                            , variableSort = sortVariableSort "s3"
                            , variableCounter = mempty
                            }
                    , inContainingChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , success "\\in{s1,s2}(\"a\", \"b\")"
            ( asParsedPattern $ InPattern In
                    { inOperandSort = sortVariableSort "s1" :: Sort
                    , inResultSort = sortVariableSort "s2"
                    , inContainedChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    , inContainingChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\mem{s1,s2}(v:s3, \"b\")"
            , "\\in{s}(v:s1, \"b\")"
            , "\\in{s,s,s}(v:s1, \"b\")"
            , "\\in{s,s}(, \"b\")"
            , "\\in{s,s}(\"b\")"
            , "\\in{s,s}(v:s1, )"
            , "\\in{s,s}(v:s1)"
            , "\\in{s,s}()"
            , "\\in{s,s}"
            , "\\in"
            , "\\in(v:s1, \"b\")"
            ]
        ]
notPatternParserTests :: [TestTree]
notPatternParserTests =
    parseTree korePatternParser
        [ success "\\not{s}(\"a\")"
            ( asParsedPattern $ NotPattern Not
                    { notSort = sortVariableSort "s" :: Sort
                    , notChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\not{s,s}(\"a\")"
            , "\\not{}(\"a\")"
            , "\\not{s}()"
            , "\\not{s}(\"a\", \"b\")"
            , "\\not{s}"
            , "\\not(\"a\")"
            ]
        ]
nextPatternParserTests :: [TestTree]
nextPatternParserTests =
    parseTree korePatternParser
        [ success "\\next{s}(\"a\")"
            ( asParsedPattern $ NextPattern Next
                    { nextSort = sortVariableSort "s"
                    , nextChild =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\next{s,s}(\"a\")"
            , "\\next{}(\"a\")"
            , "\\next{s}()"
            , "\\next{s}(\"a\", \"b\")"
            , "\\next{s}"
            , "\\next(\"a\")"
            ]
        ]
orPatternParserTests :: [TestTree]
orPatternParserTests =
    parseTree korePatternParser
        [ success "\\or{s}(\"a\", \"b\")"
            ( asParsedPattern $ OrPattern Or
                    { orSort = sortVariableSort "s" :: Sort
                    , orFirst =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    , orSecond =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\or{s,s}(\"a\", \"b\")"
            , "\\or{}(\"a\", \"b\")"
            , "\\or{s}(\"a\")"
            , "\\or{s}(\"a\", \"b\", \"c\")"
            , "\\or{s}(\"a\" \"b\")"]
        ]
rewritesPatternParserTests :: [TestTree]
rewritesPatternParserTests =
    parseTree korePatternParser
        [ success "\\rewrites{s}(\"a\", \"b\")"
            ( asParsedPattern $ RewritesPattern Rewrites
                    { rewritesSort = sortVariableSort "s"
                    , rewritesFirst =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                    , rewritesSecond =
                        asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "\\rewrites{s,s}(\"a\", \"b\")"
            , "\\rewrites{}(\"a\", \"b\")"
            , "\\rewrites{s}(\"a\")"
            , "\\rewrites{s}(\"a\", \"b\", \"c\")"
            , "\\rewrites{s}(\"a\" \"b\")"]
        ]
stringLiteralPatternParserTests :: [TestTree]
stringLiteralPatternParserTests =
    parseTree korePatternParser
        [ success "\"hello\""
            (asParsedPattern $ StringLiteralPattern (StringLiteral "hello"))
        , success "\"\""
            (asParsedPattern $ StringLiteralPattern (StringLiteral ""))
        , success "\"\\\"\""
            (asParsedPattern $ StringLiteralPattern (StringLiteral "\""))
        , FailureWithoutMessage ["", "\""]
        ]
topPatternParserTests :: [TestTree]
topPatternParserTests =
    parseTree korePatternParser
        [ success "\\top{s}()"
            (asParsedPattern $ TopPattern $ Top
                (sortVariableSort "s" :: Sort)
            )
        , FailureWithoutMessage
            ["", "\\top()", "\\top{}()", "\\top{s, s}()", "\\top{s}"]
        ]
variablePatternParserTests :: [TestTree]
variablePatternParserTests =
    parseTree korePatternParser
        [ success "v:s"
            ( asParsedPattern $ VariablePattern Variable
                { variableName = testId "v" :: Id
                , variableSort = sortVariableSort "s"
                , variableCounter = mempty
                }
            )
        , success "v:s1{s2}"
            ( asParsedPattern $ VariablePattern Variable
                { variableName = testId "v" :: Id
                , variableSort = SortActualSort SortActual
                    { sortActualName=testId "s1"
                    , sortActualSorts = [ sortVariableSort "s2" ]
                    }
                , variableCounter = mempty
                }
            )
            , FailureWithoutMessage ["", "var", "v:", ":s", "c(s)", "c{s}"]
        ]

sentenceAliasParserTests :: [TestTree]
sentenceAliasParserTests =
    parseTree koreSentenceParser
        [
          success "alias a{s1}(s2) : s3 where a{s1}(X:s2) := g{}() [\"a\"]"
            (SentenceAliasSentence $
                (SentenceAlias
                    { sentenceAliasAlias = Alias
                        { aliasConstructor = testId "a"
                        , aliasParams = [ sortVariable "s1" ]
                        }
                    , sentenceAliasSorts = [ sortVariableSort "s2"]
                    , sentenceAliasResultSort = sortVariableSort "s3"
                    , sentenceAliasLeftPattern = Application
                        { applicationSymbolOrAlias =
                            SymbolOrAlias
                                { symbolOrAliasConstructor = testId "a" :: Id
                                , symbolOrAliasParams = [ sortVariableSort "s1" ]
                                }
                        , applicationChildren =
                            [ Variable
                                { variableName = testId "X" :: Id
                                , variableSort = sortVariableSort "s2"
                                , variableCounter = mempty
                                }
                            ]
                        }
                    , sentenceAliasRightPattern =
                        asParsedPattern $ ApplicationPattern Application
                            { applicationSymbolOrAlias =
                                SymbolOrAlias
                                    { symbolOrAliasConstructor = testId "g" :: Id
                                    , symbolOrAliasParams = [ ]
                                    }
                            , applicationChildren = []
                            }
                    , sentenceAliasAttributes =
                        Attributes
                            [asParsedPattern $
                                StringLiteralPattern (StringLiteral "a")]
                    }
                :: ParsedSentenceAlias)
            )
        , success "alias a { s1 , s2 } ( s3, s4 ) : s5 where a { s1 , s2 } ( X:s3, Y:s4 ) := b { s1 , s2 } ( X:s3, Y:s4 ) [ \"a\" , \"b\" ]"
            (SentenceAliasSentence $
                (SentenceAlias
                    { sentenceAliasAlias = Alias
                        { aliasConstructor = testId "a"
                        , aliasParams =
                            [ sortVariable "s1"
                            , sortVariable "s2"
                            ]
                        }
                    , sentenceAliasSorts =
                        [ sortVariableSort "s3"
                        , sortVariableSort "s4"
                        ]
                    , sentenceAliasResultSort = sortVariableSort "s5"
                    , sentenceAliasLeftPattern =
                        Application
                            { applicationSymbolOrAlias =
                                SymbolOrAlias
                                    { symbolOrAliasConstructor = testId "a" :: Id
                                    , symbolOrAliasParams =
                                        [
                                            sortVariableSort "s1"
                                            , sortVariableSort "s2"
                                        ]
                                    }
                            , applicationChildren =
                                [ Variable
                                    { variableName = testId "X" :: Id
                                    , variableSort = sortVariableSort "s3"
                                    , variableCounter = mempty
                                    }
                                , Variable
                                    { variableName = testId "Y" :: Id
                                    , variableSort = sortVariableSort "s4"
                                    , variableCounter = mempty
                                    }
                                ]
                            }
                    , sentenceAliasRightPattern =
                        asParsedPattern $ ApplicationPattern Application
                            { applicationSymbolOrAlias =
                                SymbolOrAlias
                                    { symbolOrAliasConstructor = testId "b" :: Id
                                    , symbolOrAliasParams = [ sortVariableSort "s1", sortVariableSort "s2" ]
                                    }
                            , applicationChildren =
                                [ asParsedPattern $ VariablePattern Variable
                                    { variableName = testId "X" :: Id
                                    , variableSort = sortVariableSort "s3"
                                    , variableCounter = mempty
                                    }
                                , asParsedPattern $ VariablePattern Variable
                                    { variableName = testId "Y" :: Id
                                    , variableSort = sortVariableSort "s4"
                                    , variableCounter = mempty
                                    }
                                ]
                            }
                    , sentenceAliasAttributes =
                        Attributes
                            [ asParsedPattern $
                                StringLiteralPattern (StringLiteral "a")
                            , asParsedPattern $
                                StringLiteralPattern (StringLiteral "b")
                            ]
                    }
                :: ParsedSentenceAlias)
            )
        , success "alias #a{}() : #Char where #a{}() := #b{}() []"
            (SentenceAliasSentence $
                (SentenceAlias
                    { sentenceAliasAlias = Alias
                        { aliasConstructor = testId "#a" :: Id
                        , aliasParams = []
                        }
                    , sentenceAliasSorts = []
                    , sentenceAliasResultSort = sortVariableSort "#Char"
                    , sentenceAliasLeftPattern  =
                        Application
                            { applicationSymbolOrAlias =
                                SymbolOrAlias
                                    { symbolOrAliasConstructor =
                                        testId "#a" :: Id
                                    , symbolOrAliasParams = [ ]
                                    }
                            , applicationChildren = []
                            }
                    , sentenceAliasRightPattern =
                        (asParsedPattern . ApplicationPattern)
                            Application
                                { applicationSymbolOrAlias =
                                    SymbolOrAlias
                                        { symbolOrAliasConstructor =
                                            testId "#b" :: Id
                                        , symbolOrAliasParams = [ ]
                                        }
                                , applicationChildren = []
                                }
                    , sentenceAliasAttributes = Attributes []
                    }
                :: ParsedSentenceAlias)
            )
        , success "alias f{s}() : s where f{s}() := \\dv{s}(\"f\") []"
            (   let
                    aliasId :: Id
                    aliasId = testId "f"
                    sortVar = sortVariable "s"
                    resultSort = sortVariableSort "s"
                    aliasHead =
                        SymbolOrAlias
                            { symbolOrAliasConstructor = aliasId
                            , symbolOrAliasParams = [resultSort]
                            }
                in SentenceAliasSentence SentenceAlias
                    { sentenceAliasAlias = Alias
                        { aliasConstructor = aliasId
                        , aliasParams = [sortVar]
                        }
                    , sentenceAliasSorts = []
                    , sentenceAliasResultSort = sortVariableSort "s"
                    , sentenceAliasLeftPattern =
                        Application
                            { applicationSymbolOrAlias = aliasHead
                            , applicationChildren = []
                            }
                    , sentenceAliasRightPattern =
                        eraseAnnotations
                        $ mkDomainValue
                        $ Domain.BuiltinExternal Domain.External
                            { domainValueSort = resultSort
                            , domainValueChild =
                                Kore.AST.Pure.eraseAnnotations
                                $ mkStringLiteral "f"
                            }
                    , sentenceAliasAttributes = Attributes []
                    }
            )
        , success
            "alias rewrites{s}(s, s) : s \
            \where rewrites{s}(a : s, b : s) := \\rewrites{s}(a : s, b : s) []"
            (   let
                    aliasId :: Id
                    aliasId = testId "rewrites"
                    sortVar = sortVariable "s"
                    resultSort = sortVariableSort "s"
                    aliasHead =
                        SymbolOrAlias
                            { symbolOrAliasConstructor = aliasId
                            , symbolOrAliasParams = [resultSort]
                            }
                    var name =
                        Variable
                            { variableName = testId name
                            , variableSort = resultSort
                            , variableCounter = mempty
                            }
                    argument name = mkVar (var name)
                    varA = var "a"
                    varB = var "b"
                    argA = argument "a"
                    argB = argument "b"
                in SentenceAliasSentence SentenceAlias
                    { sentenceAliasAlias = Alias
                        { aliasConstructor = aliasId
                        , aliasParams = [sortVar]
                        }
                    , sentenceAliasSorts = [resultSort, resultSort]
                    , sentenceAliasResultSort = resultSort
                    , sentenceAliasLeftPattern =
                        Application
                            { applicationSymbolOrAlias = aliasHead
                            , applicationChildren = [varA, varB]
                            }
                    , sentenceAliasRightPattern =
                        eraseAnnotations $ mkRewrites argA argB
                    , sentenceAliasAttributes = Attributes []
                    }
            )
        , success
            "alias next{s}(s) : s \
            \where next{s}(a : s) := \\next{s}(a : s) []"
            (   let
                    aliasId :: Id
                    aliasId = testId "next"
                    sortVar = sortVariable "s"
                    resultSort = sortVariableSort "s"
                    aliasHead =
                        SymbolOrAlias
                            { symbolOrAliasConstructor = aliasId
                            , symbolOrAliasParams = [resultSort]
                            }
                    var =
                        Variable
                            { variableName = testId "a"
                            , variableSort = resultSort
                            , variableCounter = mempty
                            }
                    arg = mkVar var
                in SentenceAliasSentence SentenceAlias
                    { sentenceAliasAlias = Alias
                        { aliasConstructor = aliasId
                        , aliasParams = [sortVar]
                        }
                    , sentenceAliasSorts = [resultSort]
                    , sentenceAliasResultSort = resultSort
                    , sentenceAliasLeftPattern =
                        Application
                            { applicationSymbolOrAlias  = aliasHead
                            , applicationChildren = [var]
                            }
                    , sentenceAliasRightPattern =
                        eraseAnnotations $ mkNext arg
                    , sentenceAliasAttributes = Attributes []
                    }
            )
        , FailureWithoutMessage
            [ ""
            , "a{s1}(s2):s3[\"a\"]"
            , "alias {s1}(s2):s3[\"a\"]"
            , "alias a{s1{}}(s2):s3[\"a\"]"
            , "alias a(s2):s3[\"a\"]"
            , "alias a{s1}:s3[\"a\"]"
            , "alias a{s1}(s2)s3[\"a\"]"
            , "alias a{s1}(s2):[\"a\"]"
            , "alias a{s1}(s2)[\"a\"]"
            , "alias a{s1}(s2):s3"
            ]
        ]

sentenceAxiomParserTests :: [TestTree]
sentenceAxiomParserTests =
    parseTree koreSentenceParser
        [ success "axiom{sv1}\"a\"[\"b\"]"
            (SentenceAxiomSentence $
                (SentenceAxiom
                    { sentenceAxiomParameters =
                        [SortVariable (testId "sv1")]
                    , sentenceAxiomPattern =
                        asParsedPattern
                        $ StringLiteralPattern (StringLiteral "a")
                    , sentenceAxiomAttributes =
                        Attributes
                            [ asParsedPattern
                              $ StringLiteralPattern (StringLiteral "b")
                            ]
                    }
                :: ParsedSentenceAxiom)
            )
        {- TODO(virgil): The Scala parser allows empty sort variable lists
           while the semantics-of-k document does not. -}
        , success "axiom{}\"a\"[\"b\"]"
            (SentenceAxiomSentence $
                (SentenceAxiom
                    { sentenceAxiomParameters = []
                    , sentenceAxiomPattern =
                        asParsedPattern
                        $ StringLiteralPattern (StringLiteral "a")
                    , sentenceAxiomAttributes =
                        Attributes
                            [ asParsedPattern
                              $ StringLiteralPattern (StringLiteral "b")
                            ]
                    }
                :: ParsedSentenceAxiom)
            )
        , success "axiom { sv1 , sv2 } \"a\" [ \"b\" ] "
            (SentenceAxiomSentence $
                (SentenceAxiom
                    { sentenceAxiomParameters =
                        [ SortVariable (testId "sv1")
                        , SortVariable (testId "sv2")
                        ]
                    , sentenceAxiomPattern =
                        asParsedPattern
                        $ StringLiteralPattern (StringLiteral "a")
                    , sentenceAxiomAttributes =
                        Attributes
                            [ asParsedPattern
                              $ StringLiteralPattern (StringLiteral "b")
                            ]
                    }
                :: ParsedSentenceAxiom)
            )
        , FailureWithoutMessage
            [ ""
            , "{sv1}\"a\"[\"b\"]"
            , "axiom\"a\"[\"b\"]"
            -- , "axiom{}\"a\"[\"b\"]" See the TODO above.
            , "axiom{sv1}[\"b\"]"
            , "axiom{sv1}\"a\""
            ]
        ]

sentenceClaimParserTests :: [TestTree]
sentenceClaimParserTests =
    parseTree koreSentenceParser
        [ success "claim{sv1}\"a\"[\"b\"]"
            (SentenceClaimSentence . SentenceClaim $
                (SentenceAxiom
                    { sentenceAxiomParameters = [SortVariable (testId "sv1")]
                    , sentenceAxiomPattern =
                        asParsedPattern
                        $ StringLiteralPattern (StringLiteral "a")
                    , sentenceAxiomAttributes =
                        Attributes
                            [ asParsedPattern
                              $ StringLiteralPattern (StringLiteral "b")
                            ]
                    }
                :: ParsedSentenceAxiom)
            )
        {- TODO(virgil): The Scala parser allows empty sort variable lists
           while the semantics-of-k document does not. -}
        , success "claim{}\"a\"[\"b\"]"
            (SentenceClaimSentence . SentenceClaim $
                (SentenceAxiom
                    { sentenceAxiomParameters = []
                    , sentenceAxiomPattern =
                        asParsedPattern
                        $ StringLiteralPattern (StringLiteral "a")
                    , sentenceAxiomAttributes =
                        Attributes
                            [ asParsedPattern
                              $ StringLiteralPattern (StringLiteral "b")
                            ]
                    }
                :: ParsedSentenceAxiom)
            )
        , success "claim { sv1 , sv2 } \"a\" [ \"b\" ] "
            (SentenceClaimSentence . SentenceClaim $
                (SentenceAxiom
                    { sentenceAxiomParameters =
                        [ SortVariable (testId "sv1")
                        , SortVariable (testId "sv2")
                        ]
                    , sentenceAxiomPattern =
                        asParsedPattern
                        $ StringLiteralPattern (StringLiteral "a")
                    , sentenceAxiomAttributes =
                        Attributes
                            [ asParsedPattern
                              $ StringLiteralPattern (StringLiteral "b")
                            ]
                    }
                :: ParsedSentenceAxiom)
            )
        , FailureWithoutMessage
            [ ""
            , "{sv1}\"a\"[\"b\"]"
            , "claim\"a\"[\"b\"]"
            -- , "claim{}\"a\"[\"b\"]" See the TODO above.
            , "claim{sv1}[\"b\"]"
            , "claim{sv1}\"a\""
            ]
        ]

sentenceImportParserTests :: [TestTree]
sentenceImportParserTests =
    parseTree koreSentenceParser
        [ success "import M[\"b\"]"
            (SentenceImportSentence $
                (SentenceImport
                    { sentenceImportModuleName = ModuleName "M"
                    , sentenceImportAttributes =
                        Attributes
                            [ asParsedPattern
                              $ StringLiteralPattern (StringLiteral "b")
                            ]
                    }
                :: ParsedSentenceImport)
            )
        , FailureWithoutMessage
            [ ""
            , "M[\"b\"]"
            , "import [\"b\"]"
            , "import M"
            ]
        ]

sentenceSortParserTests :: [TestTree]
sentenceSortParserTests =
    parseTree koreSentenceParser
        [ success "sort s1 { sv1 } [ \"a\" ]"
            (SentenceSortSentence $
                (SentenceSort
                    { sentenceSortName = testId "s1"
                    , sentenceSortParameters = [ sortVariable "sv1" ]
                    , sentenceSortAttributes =
                        Attributes
                            [asParsedPattern $ StringLiteralPattern (StringLiteral "a")]
                    }
                :: ParsedSentenceSort)
            )
        {- TODO(virgil): The Scala parser allows empty sort variable lists
           while the semantics-of-k document does not. -}
        , success "sort s1 {} [ \"a\" ]"
            (SentenceSortSentence $
                (SentenceSort
                    { sentenceSortName = testId "s1"
                    , sentenceSortParameters = []
                    , sentenceSortAttributes =
                        Attributes
                            [asParsedPattern $ StringLiteralPattern (StringLiteral "a")]
                    }
                :: ParsedSentenceSort)
            )
        , FailureWithoutMessage
            [ ""
            , "s1 { sv1 } [ \"a\" ]"
            , "sort { sv1 } [ \"a\" ]"
            , "sort s1 { sv1{} } [ \"a\" ]"
            , "sort s1 [ \"a\" ]"
            , "sort s1 { sv1 } "
            , "sort { sv1 } s1 [ \"a\" ]"
            ]
        ]

sentenceSymbolParserTests :: [TestTree]
sentenceSymbolParserTests =
    parseTree koreSentenceParser
        [ success "symbol sy1 { s1 } ( s1 ) : s1 [\"a\"] "
            (SentenceSymbolSentence $
                (SentenceSymbol
                    { sentenceSymbolSymbol = Symbol
                        { symbolConstructor = testId "sy1"
                        , symbolParams = [ sortVariable "s1" ]
                        }
                    , sentenceSymbolSorts = [ sortVariableSort "s1" ]
                    , sentenceSymbolResultSort = sortVariableSort "s1"
                    , sentenceSymbolAttributes =
                        Attributes
                            [asParsedPattern $
                                StringLiteralPattern (StringLiteral "a")]
                    }
                :: ParsedSentenceSymbol)
            )
        , success "symbol sy1 {} () : s1 [] "
            (SentenceSymbolSentence $
                (SentenceSymbol
                    { sentenceSymbolSymbol = Symbol
                        { symbolConstructor = testId "sy1"
                        , symbolParams = []
                        }
                    , sentenceSymbolSorts = []
                    , sentenceSymbolResultSort = sortVariableSort "s1"
                    , sentenceSymbolAttributes = Attributes []
                    }
                :: ParsedSentenceSymbol)
            )
        , FailureWithoutMessage
            [ ""
            , "sy1 { s1 } ( s1 ) : s1 [\"a\"] "
            , "symbol { s1 } ( s1 ) : s1 [\"a\"] "
            , "symbol sy1 ( s1 ) : s1 [\"a\"] "
            , "symbol sy1 { s1 } : s1 [\"a\"] "
            , "symbol sy1 { s1 } ( s1 ) s1 [\"a\"] "
            , "symbol sy1 { s1 } ( s1 ) : [\"a\"] "
            , "symbol sy1 { s1 } ( s1 ) : s1 "
            , "symbol sy1 { s1 } ( s1 ) [\"a\"] "
            ]
        ]

sentenceHookedSortParserTests :: [TestTree]
sentenceHookedSortParserTests =
    parseTree koreSentenceParser
        [ success "hooked-sort s1 { sv1 } [ \"a\" ]"
            (SentenceHookSentence $
                (SentenceHookedSort
                    SentenceSort
                        { sentenceSortName = testId "s1"
                        , sentenceSortParameters = [ sortVariable "sv1" ]
                        , sentenceSortAttributes =
                            Attributes
                                [asParsedPattern $ StringLiteralPattern (StringLiteral "a")]
                        }

                :: ParsedSentenceHook)
            )
        {- TODO(virgil): The Scala parser allows empty sort variable lists
           while the semantics-of-k document does not. -}
        , success "hooked-sort s1 {} [ \"a\" ]"
            (SentenceHookSentence $
                (SentenceHookedSort
                    SentenceSort
                        { sentenceSortName = testId "s1"
                        , sentenceSortParameters = []
                        , sentenceSortAttributes =
                            Attributes
                                [asParsedPattern $ StringLiteralPattern (StringLiteral "a")]
                        }
                    :: ParsedSentenceHook
                )
            )
        , FailureWithoutMessage
            [ ""
            , "s1 { sv1 } [ \"a\" ]"
            , "hooked-sort { sv1 } [ \"a\" ]"
            , "hooked-sort s1 { sv1{} } [ \"a\" ]"
            , "hooked-sort s1 [ \"a\" ]"
            , "hooked-sort s1 { sv1 } "
            , "hooked-sort { sv1 } s1 [ \"a\" ]"
            ]
        ]

sentenceHookedSymbolParserTests :: [TestTree]
sentenceHookedSymbolParserTests =
    parseTree koreSentenceParser
        [ success "hooked-symbol sy1 { s1 } ( s1 ) : s1 [\"a\"] "
            (SentenceHookSentence $
                (SentenceHookedSymbol
                    SentenceSymbol
                        { sentenceSymbolSymbol = Symbol
                            { symbolConstructor = testId "sy1"
                            , symbolParams = [ sortVariable "s1" ]
                            }
                        , sentenceSymbolSorts = [ sortVariableSort "s1" ]
                        , sentenceSymbolResultSort = sortVariableSort "s1"
                        , sentenceSymbolAttributes =
                            Attributes
                                [asParsedPattern $
                                    StringLiteralPattern (StringLiteral "a")]
                        }
                    :: ParsedSentenceHook
                )
            )
        , success "hooked-symbol sy1 {} () : s1 [] "
            (SentenceHookSentence $
                (SentenceHookedSymbol
                    SentenceSymbol
                        { sentenceSymbolSymbol = Symbol
                            { symbolConstructor = testId "sy1"
                            , symbolParams = []
                            }
                        , sentenceSymbolSorts = []
                        , sentenceSymbolResultSort = sortVariableSort "s1"
                        , sentenceSymbolAttributes = Attributes []
                        }
                    :: ParsedSentenceHook
                )
            )
        , FailureWithoutMessage
            [ ""
            , "sy1 { s1 } ( s1 ) : s1 [\"a\"] "
            , "hooked-symbol { s1 } ( s1 ) : s1 [\"a\"] "
            , "hooked-symbol sy1 ( s1 ) : s1 [\"a\"] "
            , "hooked-symbol sy1 { s1 } : s1 [\"a\"] "
            , "hooked-symbol sy1 { s1 } ( s1 ) s1 [\"a\"] "
            , "hooked-symbol sy1 { s1 } ( s1 ) : [\"a\"] "
            , "hooked-symbol sy1 { s1 } ( s1 ) : s1 "
            , "hooked-symbol sy1 { s1 } ( s1 ) [\"a\"] "
            ]
        ]

attributesParserTests :: [TestTree]
attributesParserTests =
    parseTree attributesParser
        [ success "[\"a\"]"
            (Attributes
                [asParsedPattern $ StringLiteralPattern (StringLiteral "a")])
        , success "[]" (Attributes [])
        , success "[\"a\", \"b\"]"
            (Attributes
                [ asParsedPattern $ StringLiteralPattern (StringLiteral "a")
                , asParsedPattern $ StringLiteralPattern (StringLiteral "b")
                ])
        , FailureWithoutMessage ["", "a", "\"a\"", "[\"a\" \"a\"]"]
        ]


moduleParserTests :: [TestTree]
moduleParserTests =
    parseTree (moduleParser koreSentenceParser)
        [ success "module MN sort c{}[] endmodule [\"a\"]"
            Module
                { moduleName = ModuleName "MN"
                , moduleSentences =
                    [ asSentence
                        (SentenceSort
                            { sentenceSortName = testId "c"
                            , sentenceSortParameters = []
                            , sentenceSortAttributes = Attributes []
                            }
                        :: ParsedSentenceSort)
                    ]
                , moduleAttributes =
                    Attributes
                        [asParsedPattern $ StringLiteralPattern (StringLiteral "a")]
                }
        , success "module MN sort c{}[] sort c{}[] endmodule [\"a\"]"
            Module
                { moduleName = ModuleName "MN"
                , moduleSentences =
                    [ SentenceSortSentence $
                        (SentenceSort
                            { sentenceSortName = testId "c"
                            , sentenceSortParameters = []
                            , sentenceSortAttributes = Attributes []
                            }
                        :: ParsedSentenceSort)
                    , SentenceSortSentence $
                        (SentenceSort
                            { sentenceSortName = testId "c"
                            , sentenceSortParameters = []
                            , sentenceSortAttributes = Attributes []
                            }
                        :: ParsedSentenceSort)
                    ]
                , moduleAttributes =
                    Attributes
                        [asParsedPattern $ StringLiteralPattern (StringLiteral "a")]
                }
        , success "module MN endmodule []"
            Module
                { moduleName = ModuleName "MN"
                , moduleSentences = []
                , moduleAttributes = Attributes []
                }
        , FailureWithoutMessage
            [ ""
            , "MN sort c{}[] endmodule [\"a\"]"
            , "module sort c{}[] endmodule [\"a\"]"
            , "module MN sort c{}[] [\"a\"]"
            , "module MN sort c{}[] endmodule"
            ]
        ]

definitionParserTests :: [TestTree]
definitionParserTests =
    parseTree (definitionParser koreSentenceParser)
        [ success "[\"a\"] module M sort c{}[] endmodule [\"b\"]"
            Definition
                { definitionAttributes =
                    Attributes
                        [asParsedPattern $ StringLiteralPattern (StringLiteral "a")]
                , definitionModules =
                    [ Module
                        { moduleName = ModuleName "M"
                        , moduleSentences =
                            [ asSentence
                                (SentenceSort
                                    { sentenceSortName = testId "c"
                                    , sentenceSortParameters = []
                                    , sentenceSortAttributes = Attributes []
                                    }
                                :: ParsedSentenceSort)
                            ]
                        , moduleAttributes =
                            Attributes
                                [asParsedPattern $
                                    StringLiteralPattern (StringLiteral "b")]
                        }
                    ]
                }
        , success
            (  "[\"a\"] "
                ++ "module M sort c{}[] endmodule [\"b\"] "
                ++ "module N sort d{}[] endmodule [\"e\"]"
                )
            Definition
                { definitionAttributes =
                    Attributes
                        [asParsedPattern $ StringLiteralPattern (StringLiteral "a")]
                , definitionModules =
                    [ Module
                        { moduleName = ModuleName "M"
                        , moduleSentences =
                            [ asSentence
                                (SentenceSort
                                    { sentenceSortName = testId "c"
                                    , sentenceSortParameters = []
                                    , sentenceSortAttributes = Attributes []
                                    }
                                :: ParsedSentenceSort)
                            ]
                        , moduleAttributes =
                            Attributes
                                [asParsedPattern $
                                    StringLiteralPattern (StringLiteral "b")]
                        }
                    , Module
                        { moduleName = ModuleName "N"
                        , moduleSentences =
                            [ asSentence
                                (SentenceSort
                                    { sentenceSortName = testId "d"
                                    , sentenceSortParameters = []
                                    , sentenceSortAttributes = Attributes []
                                    }
                                :: ParsedSentenceSort)
                            ]
                        , moduleAttributes =
                            Attributes
                                [asParsedPattern $
                                    StringLiteralPattern (StringLiteral "e")]
                        }
                    ]
                }
        , FailureWithoutMessage
            [ ""
            , "[]"
            , "module M sort c{}[] endmodule [\"b\"]"
            ]
        ]

------------------------------------
-- Generic test utilities
------------------------------------

sortVariableSort :: Text -> Sort
sortVariableSort name = SortVariableSort (sortVariable name)

sortVariable :: Text -> SortVariable
sortVariable name = SortVariable (testId name)
