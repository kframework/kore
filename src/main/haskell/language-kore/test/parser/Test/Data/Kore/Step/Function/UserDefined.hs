{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MonoLocalBinds        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Test.Data.Kore.Step.Function.UserDefined (test_userDefinedFunction) where

import           Test.Tasty                            (TestTree)
import           Test.Tasty.HUnit                      (testCase)

import           Data.Reflection                       (give)

import           Test.Data.Kore.Comparators            ()
import           Test.Data.Kore.Step.Condition         (mockConditionEvaluator)
import           Test.Data.Kore.Step.Function          (mockFunctionEvaluator)

import           Data.Kore.AST.Common                  (Application (..),
                                                        AstLocation (..),
                                                        Id (..), Pattern (..),
                                                        SymbolOrAlias (..))
import           Data.Kore.AST.MetaOrObject
import           Data.Kore.AST.PureML                  (CommonPurePattern,
                                                        fromPurePattern)
import           Data.Kore.AST.PureToKore              (patternKoreToPure)
import           Data.Kore.Building.AsAst
import           Data.Kore.Building.Patterns
import           Data.Kore.Building.Sorts
import           Data.Kore.Error
import           Data.Kore.IndexedModule.MetadataTools (MetadataTools (..))
import           Data.Kore.MetaML.AST                  (CommonMetaPattern)
import           Data.Kore.Predicate.Predicate         (PredicateProof (..),
                                                        makeFalsePredicate,
                                                        makeTruePredicate)
import           Data.Kore.Step.BaseStep               (AxiomPattern (..))
import           Data.Kore.Step.ExpandedPattern        as ExpandedPattern (ExpandedPattern (..),
                                                                           bottom)
import           Data.Kore.Step.Function.Data          as AttemptedFunction (AttemptedFunction (..))
import           Data.Kore.Step.Function.Data          (CommonAttemptedFunction,
                                                        CommonConditionEvaluator,
                                                        CommonPurePatternFunctionEvaluator,
                                                        FunctionResultProof (..))
import           Data.Kore.Step.Function.UserDefined   (axiomFunctionEvaluator)
import           Data.Kore.Variables.Fresh.IntCounter

import           Test.Tasty.HUnit.Extensions

test_userDefinedFunction :: [TestTree]
test_userDefinedFunction =
    [ testCase "Cannot apply function if step fails"
        (assertEqualWithExplanation ""
            AttemptedFunction.NotApplicable
            (evaluateWithAxiom
                mockMetadataTools
                AxiomPattern
                    { axiomPatternLeft  =
                        asPureMetaPattern (metaF (x PatternSort))
                    , axiomPatternRight =
                        asPureMetaPattern (metaG (x PatternSort))
                    }
                (mockConditionEvaluator [])
                (mockFunctionEvaluator [])
                (asApplication (metaH (x PatternSort)))
            )
        )
    , testCase "Applies one step"
        (assertEqualWithExplanation "f(x) => g(x)"
            (AttemptedFunction.Applied ExpandedPattern
                { term = asPureMetaPattern (metaG (x PatternSort))
                , predicate = makeTruePredicate
                , substitution = []
                }
            )
            (evaluateWithAxiom
                mockMetadataTools
                AxiomPattern
                    { axiomPatternLeft  =
                        asPureMetaPattern (metaF (x PatternSort))
                    , axiomPatternRight =
                        asPureMetaPattern (metaG (x PatternSort))
                    }
                (mockConditionEvaluator
                    [   ( makeTruePredicate
                        , (makeTruePredicate, PredicateProof)
                        )
                    ]
                )
                (mockFunctionEvaluator [])
                (asApplication (metaF (x PatternSort)))
            )
        )
    , testCase "Cannot apply step with unsat condition"
        (assertEqualWithExplanation ""
            (AttemptedFunction.Applied ExpandedPattern.bottom)
            (evaluateWithAxiom
                mockMetadataTools
                AxiomPattern
                    { axiomPatternLeft  =
                        asPureMetaPattern (metaF (x PatternSort))
                    , axiomPatternRight =
                        asPureMetaPattern (metaG (x PatternSort))
                    }
                (mockConditionEvaluator
                    [   ( makeTruePredicate
                        , (makeFalsePredicate, PredicateProof)
                        )
                    ]
                )
                (mockFunctionEvaluator [])
                (asApplication (metaF (x PatternSort)))
            )
        )
    , testCase "Reevaluates the step application"
        (assertEqualWithExplanation "f(x) => g(x) and g(x) => h(x)"
            (AttemptedFunction.Applied ExpandedPattern
                { term = asPureMetaPattern (metaH (x PatternSort))
                , predicate = makeTruePredicate
                , substitution = []
                }
            )
            (evaluateWithAxiom
                mockMetadataTools
                AxiomPattern
                    { axiomPatternLeft  =
                        asPureMetaPattern (metaF (x PatternSort))
                    , axiomPatternRight =
                        asPureMetaPattern (metaG (x PatternSort))
                    }
                (mockConditionEvaluator
                     -- TODO: Remove these true->true mappings.
                    [   ( makeTruePredicate
                        , (makeTruePredicate, PredicateProof)
                        )
                    ]
                )
                (mockFunctionEvaluator
                    [   ( asPureMetaPattern (metaG (x PatternSort))
                        ,   ( ExpandedPattern
                                { term =
                                    asPureMetaPattern (metaH (x PatternSort))
                                , predicate = makeTruePredicate
                                , substitution = []
                                }
                            , FunctionResultProof
                            )
                        )
                    ]
                )
                (asApplication (metaF (x PatternSort)))
            )
        )
    , testCase "Does not reevaluate the step application with incompatible condition"
        (assertEqualWithExplanation "f(x) => g(x) and g(x) => h(x) + false"
            (AttemptedFunction.Applied ExpandedPattern.bottom)
            (evaluateWithAxiom
                mockMetadataTools
                AxiomPattern
                    { axiomPatternLeft  =
                        asPureMetaPattern (metaF (x PatternSort))
                    , axiomPatternRight =
                        asPureMetaPattern (metaG (x PatternSort))
                    }
                (mockConditionEvaluator
                    [   ( makeTruePredicate
                        , (makeTruePredicate, PredicateProof)
                        )
                    ]
                )
                (mockFunctionEvaluator
                    [   ( asPureMetaPattern (metaG (x PatternSort))
                        ,   ( ExpandedPattern
                                { term =
                                    asPureMetaPattern (metaH (x PatternSort))
                                , predicate = makeFalsePredicate
                                , substitution = []
                                }
                            , FunctionResultProof
                            )
                        )
                    ]
                )
                (asApplication (metaF (x PatternSort)))
            )
        )
    , testCase "Preserves step substitution"
        (assertEqualWithExplanation "sigma(x,x) => g(x) vs sigma(a, b)"
            (AttemptedFunction.Applied ExpandedPattern
                { term = asPureMetaPattern (metaG (b PatternSort))
                , predicate = makeTruePredicate
                , substitution =
                    [   ( asVariable (a PatternSort)
                        , asPureMetaPattern (b PatternSort)
                        )
                    ]
                }
            )
            (evaluateWithAxiom
                mockMetadataTools
                AxiomPattern
                    { axiomPatternLeft  =
                        asPureMetaPattern
                            (metaSigma (x PatternSort) (x PatternSort))
                    , axiomPatternRight =
                        asPureMetaPattern (metaG (x PatternSort))
                    }
                (mockConditionEvaluator
                    [   ( makeTruePredicate
                        , (makeTruePredicate, PredicateProof)
                        )
                    ]
                )
                (mockFunctionEvaluator [])
                (asApplication (metaSigma (a PatternSort) (b PatternSort)))
            )
        )
    , testCase "Merges the step substitution with the reevaluation one"
        (assertEqualWithExplanation
            "sigma(x,x) => g(x) vs sigma(a, b) and g(b) => h(c) + b=c"
            (AttemptedFunction.Applied ExpandedPattern
                { term = asPureMetaPattern (metaH (c PatternSort))
                , predicate = makeTruePredicate
                , substitution =
                    [   ( asVariable (a PatternSort)
                        -- TODO(virgil): Do we want normalization here?
                        , asPureMetaPattern (b PatternSort)
                        )
                    ,   ( asVariable (b PatternSort)
                        , asPureMetaPattern (c PatternSort)
                        )
                    ]
                }
            )
            (evaluateWithAxiom
                mockMetadataTools
                AxiomPattern
                    { axiomPatternLeft  =
                        asPureMetaPattern
                            (metaSigma (x PatternSort) (x PatternSort))
                    , axiomPatternRight =
                        asPureMetaPattern (metaG (x PatternSort))
                    }
                (mockConditionEvaluator
                     -- TODO: Remove these true->true mappings.
                    [   ( makeTruePredicate
                        , (makeTruePredicate, PredicateProof)
                        )
                    ]
                )
                (mockFunctionEvaluator
                    [   ( asPureMetaPattern (metaG (b PatternSort))
                        ,   ( ExpandedPattern
                                { term =
                                    asPureMetaPattern (metaH (c PatternSort))
                                , predicate = makeTruePredicate
                                , substitution =
                                    [   ( asVariable (b PatternSort)
                                        , asPureMetaPattern (c PatternSort)
                                        )
                                    ]
                                }
                            , FunctionResultProof
                            )
                        )
                    ]
                )
                (asApplication (metaSigma (a PatternSort) (b PatternSort)))
            )
        )
    -- TODO: Add a test for StepWithAxiom returning a condition.
    -- TODO: Add a test for the stepper giving up
    ]

mockMetadataTools :: MetadataTools Meta
mockMetadataTools = MetadataTools
    { isConstructor = const True
    , isFunctional = const True
    , isFunction = const False
    , getArgumentSorts = const [asAst PatternSort, asAst PatternSort]
    , getResultSort = const (asAst PatternSort)
    }

x :: MetaSort sort => sort -> MetaVariable sort
x = metaVariable "#x" AstLocationTest

a :: MetaSort sort => sort -> MetaVariable sort
a = metaVariable "#a" AstLocationTest

b :: MetaSort sort => sort -> MetaVariable sort
b = metaVariable "#b" AstLocationTest

c :: MetaSort sort => sort -> MetaVariable sort
c = metaVariable "#c" AstLocationTest

fSymbol :: SymbolOrAlias Meta
fSymbol = SymbolOrAlias
    { symbolOrAliasConstructor = Id "#f" AstLocationTest
    , symbolOrAliasParams = []
    }

newtype MetaF p1 = MetaF p1
instance (MetaPattern PatternSort p1)
    => ProperPattern Meta PatternSort (MetaF p1)
  where
    asProperPattern (MetaF p1) =
        ApplicationPattern Application
            { applicationSymbolOrAlias = fSymbol
            , applicationChildren = [asAst p1]
            }
metaF
    :: (MetaPattern PatternSort p1)
    => p1 -> MetaF p1
metaF = MetaF


gSymbol :: SymbolOrAlias Meta
gSymbol = SymbolOrAlias
    { symbolOrAliasConstructor = Id "#g" AstLocationTest
    , symbolOrAliasParams = []
    }

newtype MetaG p1 = MetaG p1
instance (MetaPattern PatternSort p1)
    => ProperPattern Meta PatternSort (MetaG p1)
  where
    asProperPattern (MetaG p1) =
        ApplicationPattern Application
            { applicationSymbolOrAlias = gSymbol
            , applicationChildren = [asAst p1]
            }
metaG
    :: (MetaPattern PatternSort p1)
    => p1 -> MetaG p1
metaG = MetaG


hSymbol :: SymbolOrAlias Meta
hSymbol = SymbolOrAlias
    { symbolOrAliasConstructor = Id "#h" AstLocationTest
    , symbolOrAliasParams = []
    }

newtype MetaH p1 = MetaH p1
instance (MetaPattern PatternSort p1)
    => ProperPattern Meta PatternSort (MetaH p1)
  where
    asProperPattern (MetaH p1) =
        ApplicationPattern Application
            { applicationSymbolOrAlias = hSymbol
            , applicationChildren = [asAst p1]
            }
metaH
    :: (MetaPattern PatternSort p1)
    => p1 -> MetaH p1
metaH = MetaH


sigmaSymbol :: SymbolOrAlias Meta
sigmaSymbol = SymbolOrAlias
    { symbolOrAliasConstructor = Id "#sigma" AstLocationTest
    , symbolOrAliasParams = []
    }

data MetaSigma p1 p2 = MetaSigma p1 p2
instance (MetaPattern PatternSort p1, MetaPattern PatternSort p2)
    => ProperPattern Meta PatternSort (MetaSigma p1 p2)
  where
    asProperPattern (MetaSigma p1 p2) =
        ApplicationPattern Application
            { applicationSymbolOrAlias = sigmaSymbol
            , applicationChildren = [asAst p1, asAst p2]
            }
metaSigma
    :: (MetaPattern PatternSort p1, MetaPattern PatternSort p2)
    => p1 -> p2 -> MetaSigma p1 p2
metaSigma = MetaSigma

asPureMetaPattern
    :: ProperPattern Meta sort patt => patt -> CommonMetaPattern
asPureMetaPattern patt =
    case patternKoreToPure Meta (asAst patt) of
        Left err  -> error (printError err)
        Right pat -> pat

asApplication
    :: ProperPattern Meta sort patt => patt
    -> Application Meta (CommonPurePattern Meta)
asApplication patt =
    case fromPurePattern (asPureMetaPattern patt) of
        ApplicationPattern app -> app
        _                      -> error "Expected an Application pattern."

evaluateWithAxiom
    :: MetaOrObject level
    => MetadataTools level
    -> AxiomPattern level
    -> CommonConditionEvaluator level
    -> CommonPurePatternFunctionEvaluator level
    -> Application level (CommonPurePattern level)
    -> CommonAttemptedFunction level
evaluateWithAxiom
    metadataTools
    axiom
    conditionEvaluator
    functionEvaluator
    app
  =
    fst $ fst $ runIntCounter
        (give metadataTools
            (axiomFunctionEvaluator
                axiom
                conditionEvaluator
                functionEvaluator
                app
            )
        )
        0
