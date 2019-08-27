module Test.Kore.Step.Function.Integration (test_functionIntegration) where

import Test.Tasty
       ( TestTree )
import Test.Tasty.HUnit
       ( testCase )

import qualified Data.Map as Map

import           Data.Sup
import qualified Kore.Internal.OrPattern as OrPattern
import           Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
import           Kore.Predicate.Predicate
                 ( makeAndPredicate, makeCeilPredicate, makeEqualsPredicate,
                 makeTruePredicate )
import qualified Kore.Predicate.Predicate as Syntax
                 ( Predicate )
import           Kore.Step.Axiom.EvaluationStrategy
                 ( builtinEvaluation, definitionEvaluation,
                 firstFullEvaluation, simplifierWithFallback )
import qualified Kore.Step.Axiom.Identifier as AxiomIdentifier
                 ( AxiomIdentifier (..) )
import           Kore.Step.Axiom.UserDefined
                 ( equalityRuleEvaluator )
import           Kore.Step.Rule
                 ( EqualityRule (EqualityRule) )
import           Kore.Step.Rule as RulePattern
                 ( RulePattern (..), rulePattern )
import           Kore.Step.Simplification.Data
import           Kore.Step.Simplification.Data as AttemptedAxiom
                 ( AttemptedAxiom (..) )
import qualified Kore.Step.Simplification.TermLike as TermLike
                 ( simplify )
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Variables.Fresh
import qualified SMT

import           Test.Kore
import           Test.Kore.Comparators ()
import qualified Test.Kore.Step.MockSymbols as Mock
import           Test.Tasty.HUnit.Extensions

test_functionIntegration :: [TestTree]
test_functionIntegration =
    [ testCase "Simple evaluation" $ do
        let expect =
                Conditional
                    { term = Mock.g Mock.c
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.singleton
                    (AxiomIdentifier.Application Mock.functionalConstr10Id)
                    (axiomEvaluator
                        (Mock.functionalConstr10 (mkVar Mock.x))
                        (Mock.g (mkVar Mock.x))
                    )
                )
                (Mock.functionalConstr10 Mock.c)
        assertEqualWithExplanation "" expect actual

    , testCase "Simple evaluation (builtin branch)" $ do
        let expect =
                Conditional
                    { term = Mock.g Mock.c
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.singleton
                    (AxiomIdentifier.Application Mock.functionalConstr10Id)
                    (builtinEvaluation $ axiomEvaluator
                        (Mock.functionalConstr10 (mkVar Mock.x))
                        (Mock.g (mkVar Mock.x))
                    )
                )
                (Mock.functionalConstr10 Mock.c)
        assertEqualWithExplanation "" expect actual

    , testCase "Simple evaluation (Axioms & Builtin branch, Builtin works)"
      $ do
        let expect =
                Conditional
                    { term = Mock.g Mock.c
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.singleton
                    (AxiomIdentifier.Application Mock.functionalConstr10Id)
                    (simplifierWithFallback
                        (builtinEvaluation $ axiomEvaluator
                            (Mock.functionalConstr10 (mkVar Mock.x))
                            (Mock.g (mkVar Mock.x))
                        )
                        ( axiomEvaluator
                            (Mock.functionalConstr10 (mkVar Mock.x))
                            (mkVar Mock.x)
                        )
                    )
                )
                (Mock.functionalConstr10 Mock.c)
        assertEqualWithExplanation "" expect actual

    , testCase "Simple evaluation (Axioms & Builtin branch, Builtin fails)"
      $ do
        let expect =
                Conditional
                    { term = Mock.g Mock.c
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.singleton
                    (AxiomIdentifier.Application Mock.functionalConstr10Id)
                    (simplifierWithFallback
                        (builtinEvaluation $ BuiltinAndAxiomSimplifier
                            (\_ _ _ _ -> notApplicableAxiomEvaluator)
                        )
                        ( axiomEvaluator
                            (Mock.functionalConstr10 (mkVar Mock.x))
                            (Mock.g (mkVar Mock.x))
                        )
                    )
                )
                (Mock.functionalConstr10 Mock.c)
        assertEqualWithExplanation "" expect actual

    , testCase "Evaluates inside functions" $ do
        let expect =
                Conditional
                    { term = Mock.functional10 (Mock.functional10 Mock.c)
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.singleton
                    (AxiomIdentifier.Application Mock.functionalConstr10Id)
                    ( axiomEvaluator
                        (Mock.functionalConstr10 (mkVar Mock.x))
                        (Mock.functional10 (mkVar Mock.x))
                    )
                )
                (Mock.functionalConstr10 (Mock.functionalConstr10 Mock.c))
        assertEqualWithExplanation "" expect actual

    , testCase "Evaluates 'or'" $ do
        let expect =
                Conditional
                    { term =
                        mkOr
                            (Mock.functional10 (Mock.functional10 Mock.c))
                            (Mock.functional10 (Mock.functional10 Mock.d))
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.singleton
                    (AxiomIdentifier.Application Mock.functionalConstr10Id)
                    ( axiomEvaluator
                        (Mock.functionalConstr10 (mkVar Mock.x))
                        (Mock.functional10 (mkVar Mock.x))
                    )
                )
                (Mock.functionalConstr10
                    (mkOr
                        (Mock.functionalConstr10 Mock.c)
                        (Mock.functionalConstr10 Mock.d)
                    )
                )
        assertEqualWithExplanation "" expect actual

    , testCase "Evaluates on multiple branches" $ do
        let expect =
                Conditional
                    { term =
                        Mock.functional10
                            (Mock.functional20
                                (Mock.functional10 Mock.c)
                                (Mock.functional10 Mock.c)
                            )
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.singleton
                    (AxiomIdentifier.Application Mock.functionalConstr10Id)
                    ( axiomEvaluator
                        (Mock.functionalConstr10 (mkVar Mock.x))
                        (Mock.functional10 (mkVar Mock.x))
                    )
                )
                (Mock.functionalConstr10
                    (Mock.functional20
                        (Mock.functionalConstr10 Mock.c)
                        (Mock.functionalConstr10 Mock.c)
                    )
                )
        assertEqualWithExplanation "" expect actual

    , testCase "Returns conditions" $ do
        let expect =
                Conditional
                    { term = Mock.f Mock.d
                    , predicate = makeCeilPredicate (Mock.plain10 Mock.e)
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.singleton
                    (AxiomIdentifier.Application Mock.cId)
                    ( appliedMockEvaluator Conditional
                        { term   = Mock.d
                        , predicate = makeCeilPredicate (Mock.plain10 Mock.e)
                        , substitution = mempty
                        }
                    )
                )
                (Mock.f Mock.c)
        assertEqualWithExplanation "" expect actual

    , testCase "Merges conditions" $ do
        let expect =
                Conditional
                    { term = Mock.functional11 (Mock.functional20 Mock.e Mock.e)
                    , predicate =
                        makeAndPredicate
                            (makeCeilPredicate Mock.cg)
                            (makeCeilPredicate Mock.cf)
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.fromList
                    [   ( AxiomIdentifier.Application Mock.cId
                        , appliedMockEvaluator Conditional
                            { term = Mock.e
                            , predicate = makeCeilPredicate Mock.cg
                            , substitution = mempty
                            }
                        )
                    ,   ( AxiomIdentifier.Application Mock.dId
                        , appliedMockEvaluator Conditional
                            { term = Mock.e
                            , predicate = makeCeilPredicate Mock.cf
                            , substitution = mempty
                            }
                        )
                    ,   ( AxiomIdentifier.Application Mock.functionalConstr10Id
                        , axiomEvaluator
                            (Mock.functionalConstr10 (mkVar Mock.x))
                            (Mock.functional11 (mkVar Mock.x))
                        )
                    ]
                )
                (Mock.functionalConstr10 (Mock.functional20 Mock.c Mock.d))
        assertEqualWithExplanation "" expect actual

    , testCase "Reevaluates user-defined function results." $ do
        let expect =
                Conditional
                    { term = Mock.f Mock.e
                    , predicate = makeEqualsPredicate (Mock.f Mock.e) Mock.e
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.fromList
                    [   ( AxiomIdentifier.Application Mock.cId
                        , axiomEvaluator Mock.c Mock.d
                        )
                    ,   ( AxiomIdentifier.Application Mock.dId
                        , appliedMockEvaluator Conditional
                            { term = Mock.e
                            , predicate =
                                makeEqualsPredicate (Mock.f Mock.e) Mock.e
                            , substitution = mempty
                            }
                        )
                    ]
                )
                (Mock.f Mock.c)
        assertEqualWithExplanation "" expect actual

    , testCase "Merges substitutions with reevaluation ones." $ do
        let expect =
                Conditional
                    { term = Mock.f Mock.e
                    , predicate = makeTruePredicate
                    , substitution = Substitution.unsafeWrap
                        [   ( Mock.var_x_1
                            , Mock.a
                            )
                        ,   ( Mock.var_z_1
                            , Mock.a
                            )
                        ]
                    }
        actual <-
            evaluate
                (Map.fromList
                    [   ( AxiomIdentifier.Application Mock.cId
                        , appliedMockEvaluator Conditional
                            { term = Mock.d
                            , predicate = makeTruePredicate
                            , substitution = Substitution.unsafeWrap
                                [   ( Mock.x
                                    , mkVar Mock.z
                                    )
                                ]
                            }
                        )
                    ,   ( AxiomIdentifier.Application Mock.dId
                        , appliedMockEvaluator Conditional
                            { term = Mock.e
                            , predicate = makeTruePredicate
                            , substitution = Substitution.unsafeWrap
                                [   ( Mock.x
                                    , Mock.a
                                    )
                                ]
                            }
                        )
                    ]
                )
                (Mock.f Mock.c)
        assertEqualWithExplanation "" expect actual

    , testCase "Simplifies substitution-predicate." $ do
        -- Mock.plain10 below prevents:
        -- 1. unification without substitution.
        -- 2. Transforming the 'and' in an equals predicate,
        --    as it would happen for functions.
        let expect =
                Conditional
                    { term = Mock.a
                    , predicate =
                        makeCeilPredicate
                            (Mock.plain10 Mock.cf)
                    , substitution = Substitution.unsafeWrap
                        [ (Mock.var_x_1, Mock.cf), (Mock.var_y_1, Mock.b) ]
                    }
        actual <-
            evaluate
                (Map.fromList
                    [   ( AxiomIdentifier.Application Mock.fId
                        , appliedMockEvaluator Conditional
                            { term = Mock.a
                            , predicate =
                                makeCeilPredicate
                                    (mkAnd
                                        (Mock.constr20
                                            (Mock.plain10 Mock.cf)
                                            Mock.b
                                        )
                                        (Mock.constr20
                                            (Mock.plain10 (mkVar Mock.x))
                                            (mkVar Mock.y)
                                        )
                                    )
                            , substitution =
                                Substitution.wrap [(Mock.x, Mock.cf)]
                            }
                        )
                    ]
                )
                (Mock.f (mkVar Mock.x))
        assertEqualWithExplanation "" expect actual

    , testCase "Evaluates only simplifications." $ do
        let expect =
                Conditional
                    { term = Mock.b
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.fromList
                    [   ( AxiomIdentifier.Application Mock.fId
                        , simplifierWithFallback
                            (appliedMockEvaluator Conditional
                                { term = Mock.b
                                , predicate = makeTruePredicate
                                , substitution = mempty
                                }
                            )
                            (definitionEvaluation
                                [ axiom
                                    (Mock.f (mkVar Mock.y))
                                    Mock.a
                                    makeTruePredicate
                                ]
                            )
                        )
                    ]
                )
                (Mock.f (mkVar Mock.x))
        assertEqualWithExplanation "" expect actual

    , testCase "Picks first matching simplification." $ do
        let expect =
                Conditional
                    { term = Mock.b
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.fromList
                    [   ( AxiomIdentifier.Application Mock.fId
                        , simplifierWithFallback
                            (firstFullEvaluation
                                [ axiomEvaluator
                                    (Mock.f (Mock.g (mkVar Mock.x)))
                                    Mock.c
                                ,  appliedMockEvaluator Conditional
                                    { term = Mock.b
                                    , predicate = makeTruePredicate
                                    , substitution = mempty
                                    }
                                ,  appliedMockEvaluator Conditional
                                    { term = Mock.c
                                    , predicate = makeTruePredicate
                                    , substitution = mempty
                                    }
                                ]
                            )
                            (definitionEvaluation
                                [ axiom
                                    (Mock.f (mkVar Mock.y))
                                    Mock.a
                                    makeTruePredicate
                                ]
                            )
                        )
                    ]
                )
                (Mock.f (mkVar Mock.x))
        assertEqualWithExplanation "" expect actual

    , testCase "Falls back to evaluating the definition." $ do
        let expect =
                Conditional
                    { term = Mock.a
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.fromList
                    [   ( AxiomIdentifier.Application Mock.fId
                        , simplifierWithFallback
                            (axiomEvaluator
                                (Mock.f (Mock.g (mkVar Mock.x)))
                                Mock.b
                            )
                            (definitionEvaluation
                                [ axiom
                                    (Mock.f (mkVar Mock.y))
                                    Mock.a
                                    makeTruePredicate
                                ]
                            )
                        )
                    ]
                )
                (Mock.f (mkVar Mock.x))
        assertEqualWithExplanation "" expect actual

    , testCase "Multiple definition branches." $ do
        let expect =
                Conditional
                    { term = mkOr
                        (mkAnd Mock.a (mkCeil Mock.testSort Mock.cf))
                        (mkAnd Mock.b (mkNot (mkCeil Mock.testSort Mock.cf)))
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <-
            evaluate
                (Map.fromList
                    [   ( AxiomIdentifier.Application Mock.fId
                        , simplifierWithFallback
                            (axiomEvaluator
                                (Mock.f (Mock.g (mkVar Mock.x)))
                                Mock.c
                            )
                            (definitionEvaluation
                                [ axiom
                                    (Mock.f (mkVar Mock.y))
                                    Mock.a
                                    (makeCeilPredicate Mock.cf)
                                , axiom
                                    (Mock.f (mkVar Mock.y))
                                    Mock.b
                                    makeTruePredicate
                                ]
                            )
                        )
                    ]
                )
                (Mock.f (mkVar Mock.x))
        assertEqualWithExplanation "" expect actual
    ]

axiomEvaluator
    :: TermLike Variable
    -> TermLike Variable
    -> BuiltinAndAxiomSimplifier
axiomEvaluator left right =
    BuiltinAndAxiomSimplifier
        (equalityRuleEvaluator (axiom left right makeTruePredicate))

axiom
    :: TermLike Variable
    -> TermLike Variable
    -> Syntax.Predicate Variable
    -> EqualityRule Variable
axiom left right predicate =
    EqualityRule (RulePattern.rulePattern left right) { requires = predicate }

appliedMockEvaluator
    :: Pattern Variable -> BuiltinAndAxiomSimplifier
appliedMockEvaluator result =
    BuiltinAndAxiomSimplifier
    $ mockEvaluator
    $ AttemptedAxiom.Applied AttemptedAxiomResults
        { results = OrPattern.fromPatterns
            [Test.Kore.Step.Function.Integration.mapVariables result]
        , remainders = OrPattern.fromPatterns []
        }

mapVariables
    ::  ( FreshVariable variable
        , SortedVariable variable
        )
    => Pattern Variable
    -> Pattern variable
mapVariables =
    Pattern.mapVariables $ \v ->
        fromVariable v { variableCounter = Just (Element 1) }

mockEvaluator
    :: Monad simplifier
    => AttemptedAxiom variable
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -> TermLike variable
    -> simplifier (AttemptedAxiom variable)
mockEvaluator evaluation _ _ _ _ = return evaluation

evaluate
    :: BuiltinAndAxiomSimplifierMap
    -> TermLike Variable
    -> IO (Pattern Variable)
evaluate functionIdToEvaluator patt =
    SMT.runSMT SMT.defaultConfig emptyLogger
    $ evalSimplifier Mock.env { simplifierAxioms = functionIdToEvaluator }
    $ TermLike.simplify patt
