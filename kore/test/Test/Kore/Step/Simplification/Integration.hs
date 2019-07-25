module Test.Kore.Step.Simplification.Integration
    ( test_simplificationIntegration
    , test_substituteMap
    , test_substituteList
    , test_substitute
    ) where

import Test.Tasty
       ( TestTree )
import Test.Tasty.HUnit
       ( testCase )

import           Data.Default
                 ( Default (..) )
import qualified Data.Map.Strict as Map

import qualified Kore.Builtin.Map as Map
import           Kore.Internal.OrPattern
                 ( OrPattern )
import qualified Kore.Internal.OrPattern as OrPattern
import           Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
import           Kore.Predicate.Predicate
                 ( makeCeilPredicate, makeTruePredicate )
import           Kore.Step.Axiom.EvaluationStrategy
                 ( builtinEvaluation, simplifierWithFallback )
import qualified Kore.Step.Axiom.Identifier as AxiomIdentifier
                 ( AxiomIdentifier (..) )
import           Kore.Step.Axiom.Registry
                 ( axiomPatternsToEvaluators )
import           Kore.Step.Rule
                 ( EqualityRule (EqualityRule), RulePattern (RulePattern) )
import           Kore.Step.Rule as RulePattern
                 ( RulePattern (..) )
import           Kore.Step.Simplification.Data
import qualified Kore.Step.Simplification.Pattern as Pattern
                 ( simplify )
import           Kore.SubstVar
                 ( SubstVar (..) )
import qualified Kore.Unification.Substitution as Substitution
import qualified SMT

import           Test.Kore
import           Test.Kore.Comparators ()
import qualified Test.Kore.Step.MockSymbols as Mock
import           Test.Tasty.HUnit.Extensions

test_simplificationIntegration :: [TestTree]
test_simplificationIntegration =
    [ testCase "owise condition - main case" $ do
        let expect = OrPattern.fromPatterns []
        actual <-
            evaluate
                Conditional
                    { term =
                        -- Use the exact form we expect from an owise condition
                        -- for f(constr10(x)) = something
                        --     f(x) = something-else [owise]
                        mkAnd
                            (mkNot
                                (mkOr
                                    (mkExists Mock.x
                                        (mkAnd
                                            mkTop_
                                            (mkAnd
                                                (mkCeil_
                                                    (mkAnd
                                                        (Mock.constr10
                                                            (mkVar Mock.x)
                                                        )
                                                        (Mock.constr10 Mock.a)
                                                    )
                                                )
                                                mkTop_
                                            )
                                        )
                                    )
                                    mkBottom_
                                )
                            )
                            mkTop_
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual

    , testCase "owise condition - owise case" $ do
        let expect = OrPattern.fromPatterns [Pattern.top]
        actual <-
            evaluate
                Conditional
                    { term =
                        -- Use the exact form we expect from an owise condition
                        -- for f(constr10(x)) = something
                        --     f(x) = something-else [owise]
                        mkAnd
                            (mkNot
                                (mkOr
                                    (mkExists Mock.x
                                        (mkAnd
                                            mkTop_
                                            (mkAnd
                                                (mkCeil_
                                                    (mkAnd
                                                        (Mock.constr10
                                                            (mkVar Mock.x)
                                                        )
                                                        (Mock.constr11 Mock.a)
                                                    )
                                                )
                                                mkTop_
                                            )
                                        )
                                    )
                                    mkBottom_
                                )
                            )
                            mkTop_
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual

     , testCase "map-like simplification" $ do
        let expect =
                OrPattern.fromPatterns
                    [ Conditional
                        { term = mkTop_
                        , predicate = makeCeilPredicate
                            (mkAnd
                                (Mock.plain10 Mock.cf)
                                (Mock.plain10 (mkVar Mock.x))
                            )
                        , substitution = Substitution.unsafeWrap
                            [(RegVar Mock.y, Mock.b)]
                        }
                    ]
        actual <-
            evaluate
                Conditional
                    { term = mkCeil_
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
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual
    , testCase "map function, non-matching" $ do
        let
            expect = OrPattern.fromPatterns
                [ Conditional
                    { term =
                        mkEvaluated
                        $ Mock.function20MapTest (Mock.builtinMap []) Mock.a
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
                ]
        actual <-
            evaluateWithAxioms
                (axiomPatternsToEvaluators
                    (Map.fromList
                        [   ( AxiomIdentifier.Application
                                Mock.function20MapTestId
                            ,   [ EqualityRule RulePattern
                                    { left =
                                        Mock.function20MapTest
                                            (Mock.concatMap
                                                (Mock.elementMap
                                                    (mkVar Mock.x)
                                                    (mkVar Mock.y)
                                                )
                                                (mkVar Mock.m)
                                            )
                                            (mkVar Mock.x)
                                    , right = mkVar Mock.y
                                    , requires = makeTruePredicate
                                    , ensures = makeTruePredicate
                                    , attributes = def
                                    }
                                ]
                            )
                        ]
                    )
                )
                Conditional
                    { term = Mock.function20MapTest (Mock.builtinMap []) Mock.a
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual
    , testCase "map function, matching" $ do
        let
            expect = OrPattern.fromPatterns
                [ Conditional
                    { term = Mock.c
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
                ]
        actual <-
            evaluateWithAxioms
                (axiomPatternsToEvaluators
                    (Map.fromList
                        [   ( AxiomIdentifier.Application
                                Mock.function20MapTestId
                            ,   [ EqualityRule RulePattern
                                    { left =
                                        Mock.function20MapTest
                                            (Mock.concatMap
                                                (Mock.elementMap
                                                    (mkVar Mock.x)
                                                    (mkVar Mock.y)
                                                )
                                                (mkVar Mock.m)
                                            )
                                            (mkVar Mock.x)
                                    , right = mkVar Mock.y
                                    , requires = makeTruePredicate
                                    , ensures = makeTruePredicate
                                    , attributes = def
                                    }
                                ]
                            )
                        ]
                    )
                )
                Conditional
                    { term =
                        Mock.function20MapTest
                            (Mock.builtinMap [(Mock.a, Mock.c)]) Mock.a
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual
    , testCase "exists variable equality" $ do
        let
            expect = OrPattern.top
        actual <-
            evaluateWithAxioms
                Map.empty
                Conditional
                    { term =
                        mkExists
                            Mock.x
                            (mkEquals_ (mkVar Mock.x) (mkVar Mock.y))
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual
    , testCase "exists variable equality reverse" $ do
        let
            expect = OrPattern.top
        actual <-
            evaluateWithAxioms
                Map.empty
                Conditional
                    { term =
                        mkExists
                            Mock.x
                            (mkEquals_ (mkVar Mock.y) (mkVar Mock.x))
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual
    , testCase "exists variable equality" $ do
        let
            expect = OrPattern.top
        actual <-
            evaluateWithAxioms
                Map.empty
                Conditional
                    { term =
                        mkExists
                            Mock.x
                            (mkEquals_ (mkVar Mock.x) (mkVar Mock.y))
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual
    , testCase "exists variable equality reverse" $ do
        let
            expect = OrPattern.top
        actual <-
            evaluateWithAxioms
                Map.empty
                Conditional
                    { term =
                        mkExists
                            Mock.x
                            (mkEquals_ (mkVar Mock.y) (mkVar Mock.x))
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual
    , testCase "new variable quantification" $ do
        let
            expect = OrPattern.fromPatterns
                [ Conditional
                    { term = mkExists Mock.x (Mock.f (mkVar Mock.x))
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
                ]
        actual <-
            evaluateWithAxioms
                (axiomPatternsToEvaluators $ Map.fromList
                    [   ( AxiomIdentifier.Application Mock.cfId
                        ,   [ EqualityRule RulePattern
                                { left = Mock.cf
                                , right = Mock.f (mkVar Mock.x)
                                , requires = makeTruePredicate
                                , ensures = makeTruePredicate
                                , attributes = def
                                }
                            ]
                        )
                    ]
                )
                Conditional
                    { term = Mock.cf
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        assertEqualWithExplanation "" expect actual
    ]

test_substitute :: [TestTree]
test_substitute =
    [ testCase "Substitution under unary functional constructor" $ do
        let expect =
                OrPattern.fromPatterns
                    [ Pattern.Conditional
                        { term =
                            Mock.functionalConstr20
                                Mock.a
                                (Mock.functionalConstr10 (mkVar Mock.x))
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [ (RegVar Mock.x, Mock.a)
                            , (RegVar Mock.y, Mock.functionalConstr10 Mock.a)
                            ]
                        }
                    ]
        actual <-
            evaluate
                (Pattern.fromTermLike
                    (mkAnd
                        (Mock.functionalConstr20
                            (mkVar Mock.x)
                            (Mock.functionalConstr10 (mkVar Mock.x))
                        )
                        (Mock.functionalConstr20 Mock.a (mkVar Mock.y))
                    )
                )
        assertEqualWithExplanation
            "Expected substitution under unary functional constructor"
            expect
            actual

    , testCase "Substitution" $ do
        let expect =
                OrPattern.fromPatterns
                    [ Pattern.Conditional
                        { term = Mock.functionalConstr20 Mock.a (mkVar Mock.y)
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [ (RegVar Mock.x, Mock.a)
                            , (RegVar Mock.y, Mock.a)
                            ]
                        }
                    ]
        actual <-
            evaluate
                (Pattern.fromTermLike
                    (mkAnd
                        (Mock.functionalConstr20
                            (mkVar Mock.x)
                            (mkVar Mock.x)
                        )
                        (Mock.functionalConstr20 Mock.a (mkVar Mock.y))
                    )
                )
        assertEqualWithExplanation "Expected substitution" expect actual
    ]

test_substituteMap :: [TestTree]
test_substituteMap =
    [ testCase "Substitution applied to Map elements" $ do
        let testMapX =
                Mock.sortInjection Mock.testSort
                $ mkDomainBuiltinMap [(Mock.a, mkVar Mock.x)]
            testMapA =
                Mock.sortInjection Mock.testSort
                $ mkDomainBuiltinMap [(Mock.a, Mock.a)]
            expect =
                OrPattern.fromPatterns
                    [ Pattern.Conditional
                        { term = Mock.functionalConstr20 Mock.a testMapX
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [ (RegVar Mock.x, Mock.a)
                            , (RegVar Mock.y, testMapA)
                            ]
                        }
                    ]
        actual <-
            (evaluate . Pattern.fromTermLike)
                (mkAnd
                    (Mock.functionalConstr20 (mkVar Mock.x) testMapX)
                    (Mock.functionalConstr20 Mock.a (mkVar Mock.y))
                )
        assertEqualWithExplanation
            "Expected substitution applied to Map elements"
            expect
            actual
    ]
  where
    mkDomainBuiltinMap = Mock.builtinMap

test_substituteList :: [TestTree]
test_substituteList =
    [ testCase "Substitution applied to List elements" $ do
        let testListX =
                Mock.sortInjection Mock.testSort
                $ mkDomainBuiltinList [Mock.a, mkVar Mock.x]
            testListA =
                Mock.sortInjection Mock.testSort
                $ mkDomainBuiltinList [Mock.a, Mock.a]
            expect =
                OrPattern.fromPatterns
                    [ Pattern.Conditional
                        { term = Mock.functionalConstr20 Mock.a testListX
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [ (RegVar Mock.x, Mock.a)
                            , (RegVar Mock.y, testListA)
                            ]
                        }
                    ]
        actual <-
            (evaluate . Pattern.fromTermLike)
                (mkAnd
                    (Mock.functionalConstr20 (mkVar Mock.x) testListX)
                    (Mock.functionalConstr20 Mock.a (mkVar Mock.y))
                )
        assertEqualWithExplanation
            "Expected substitution applied to List elements"
            expect
            actual
    ]
  where
    mkDomainBuiltinList = Mock.builtinList

evaluate :: Pattern Variable -> IO (OrPattern Variable)
evaluate patt =
    evaluateWithAxioms Map.empty patt

evaluateWithAxioms
    :: BuiltinAndAxiomSimplifierMap
    -> Pattern Variable
    -> IO (OrPattern Variable)
evaluateWithAxioms axioms =
    SMT.runSMT SMT.defaultConfig emptyLogger
    . evalSimplifier env
    . Pattern.simplify
  where
    env = Mock.env { simplifierAxioms = axiomIdToSimplifier }
    axiomIdToSimplifier :: BuiltinAndAxiomSimplifierMap
    axiomIdToSimplifier =
        Map.unionWith
            simplifierWithFallback
            builtinAxioms
            axioms
    builtinAxioms :: BuiltinAndAxiomSimplifierMap
    builtinAxioms =
        Map.fromList
            [   ( AxiomIdentifier.Application Mock.concatMapId
                , builtinEvaluation Map.evalConcat
                )
            ,   ( AxiomIdentifier.Application Mock.elementMapId
                , builtinEvaluation Map.evalElement
                )
            ]
