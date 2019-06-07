module Test.Kore.Step.Simplification.AndTerms where

import Test.Tasty
       ( TestTree, testGroup )
import Test.Tasty.HUnit
       ( testCase )

import           Control.Error
                 ( MaybeT (..) )
import qualified Control.Error as Error
import           Data.Default
                 ( Default (..) )
import qualified Data.Map as Map
import qualified Data.Set as Set

import qualified Kore.Attribute.Axiom as Attribute
import           Kore.Attribute.Simplification
                 ( Simplification (Simplification) )
import qualified Kore.Builtin.Set as Set
                 ( asInternal )
import qualified Kore.Internal.MultiOr as MultiOr
                 ( extractPatterns )
import           Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
import           Kore.Predicate.Predicate
                 ( makeAndPredicate, makeCeilPredicate, makeEqualsPredicate,
                 makeTruePredicate )
import qualified Kore.Step.Axiom.Identifier as AxiomIdentifier
import           Kore.Step.Axiom.Registry
                 ( axiomPatternsToEvaluators )
import           Kore.Step.Rule
                 ( EqualityRule (EqualityRule), RulePattern (RulePattern) )
import qualified Kore.Step.Rule as RulePattern
                 ( RulePattern (..) )
import           Kore.Step.Simplification.AndTerms
                 ( termAnd, termEquals, termUnification )
import           Kore.Step.Simplification.Data
                 ( BuiltinAndAxiomSimplifierMap )
import           Kore.Step.Simplification.Data
                 ( Env (..), evalSimplifier )
import qualified Kore.Step.Simplification.Data as BranchT
                 ( gather )
import qualified Kore.Unification.Substitution as Substitution
import qualified Kore.Unification.Unify as Monad.Unify
import qualified SMT

import           Test.Kore
import           Test.Kore.Comparators ()
import qualified Test.Kore.Step.MockSymbols as Mock
import           Test.Tasty.HUnit.Extensions

test_andTermsSimplification :: [TestTree]
test_andTermsSimplification =
    [ testGroup "Predicates"
        [ testCase "\\and{s}(f{}(a), \\top{s}())" $ do
            let expected =
                    Conditional
                        { term = fOfA
                        , predicate = makeTruePredicate
                        , substitution = mempty
                        }
            actual <- simplifyUnify fOfA mkTop_
            assertEqualWithExplanation "" ([expected], Just [expected]) actual

        , testCase "\\and{s}(\\top{s}(), f{}(a))" $ do
            let expected =
                    Conditional
                        { term = fOfA
                        , predicate = makeTruePredicate
                        , substitution = mempty
                        }
            actual <- simplifyUnify mkTop_ fOfA
            assertEqualWithExplanation "" ([expected], Just [expected]) actual

        , testCase "\\and{s}(f{}(a), \\bottom{s}())" $ do
            let expect =
                    ( [Pattern.bottom]
                    , Just [Pattern.bottom]
                    )
            actual <- simplifyUnify fOfA mkBottom_
            assertEqualWithExplanation "" expect actual

        , testCase "\\and{s}(\\bottom{s}(), f{}(a))" $ do
            let expect =
                    ( [Pattern.bottom]
                    , Just [Pattern.bottom]
                    )
            actual <- simplifyUnify mkBottom_ fOfA
            assertEqualWithExplanation "" expect actual
        ]

    , testCase "equal patterns and" $ do
        let expect =
                Conditional
                    { term = fOfA
                    , predicate = makeTruePredicate
                    , substitution = mempty
                    }
        actual <- simplifyUnify fOfA fOfA
        assertEqualWithExplanation "" ([expect], Just [expect]) actual

    , testGroup "variable function and"
        [ testCase "\\and{s}(x:s, f{}(a))" $ do
            let expect =
                    Conditional
                        { term = fOfA
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap [(Mock.x, fOfA)]
                        }
            actual <- simplifyUnify (mkVar Mock.x) fOfA
            assertEqualWithExplanation "" ([expect], Just [expect]) actual

        , testCase "\\and{s}(f{}(a), x:s)" $ do
            let expect =
                    Conditional
                        { term = fOfA
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap [(Mock.x, fOfA)]
                        }
            actual <- simplifyUnify fOfA (mkVar Mock.x)
            assertEqualWithExplanation "" ([expect], Just [expect]) actual
        ]

    , testGroup "injective head and"
        [ testCase "same head, different child" $ do
            let expect =
                    Conditional
                        { term = Mock.injective10 fOfA
                        , predicate = makeEqualsPredicate fOfA gOfA
                        , substitution = mempty
                        }
            actual <-
                simplifyUnify
                    (Mock.injective10 fOfA) (Mock.injective10 gOfA)
            assertEqualWithExplanation "" ([expect], Just [expect]) actual
        , testCase "same head, same child" $ do
            let expected =
                    Conditional
                        { term = Mock.injective10 fOfA
                        , predicate = makeTruePredicate
                        , substitution = mempty
                        }
            actual <-
                simplifyUnify
                    (Mock.injective10 fOfA) (Mock.injective10 fOfA)
            assertEqualWithExplanation "" ([expected], Just [expected]) actual
        , testCase "different head" $ do
            let expect =
                    (   [ Conditional
                            { term =
                                mkAnd
                                    (Mock.injective10 fOfA)
                                    (Mock.injective11 gOfA)
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                        ]
                    , Nothing
                    )
            actual <-
                simplifyUnify
                    (Mock.injective10 fOfA) (Mock.injective11 gOfA)
            assertEqualWithExplanation "" expect actual
        ]

    , testGroup "sort injection and"
        [ testCase "same head, different child" $ do
            let expect =
                    Conditional
                        { term = Mock.sortInjection10 Mock.cfSort0
                        , predicate =
                            makeEqualsPredicate Mock.cfSort0 Mock.cgSort0
                        , substitution = mempty
                        }
            actual <-
                simplifyUnify
                    (Mock.sortInjection10 Mock.cfSort0)
                    (Mock.sortInjection10 Mock.cgSort0)
            assertEqualWithExplanation "" ([expect], Just [expect]) actual
        , testCase "same head, same child" $ do
            let expect =
                    Conditional
                        { term =
                            Mock.sortInjection10 Mock.cfSort0
                        , predicate = makeTruePredicate
                        , substitution = mempty
                        }
            actual <-
                simplifyUnify
                    (Mock.sortInjection10 Mock.cfSort0)
                    (Mock.sortInjection10 Mock.cfSort0)
            assertEqualWithExplanation "" ([expect], Just [expect]) actual
        , testCase "different head, not subsort" $ do
            let expect = ([], Just [])
            actual <-
                simplifyUnify
                    (Mock.sortInjectionSubToTop Mock.plain00Subsort)
                    (Mock.sortInjection0ToTop Mock.plain00Sort0)
            assertEqualWithExplanation "" expect actual
        , testCase "different head, subsort first" $ do
            let expect =
                    (   [ Conditional
                            { term =
                                Mock.sortInjectionSubToTop
                                    (mkAnd
                                        (Mock.sortInjectionSubSubToSub
                                            Mock.plain00SubSubsort
                                        )
                                        Mock.plain00Subsort
                                    )
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                        ]
                    , Nothing
                    )
            actual <-
                simplifyUnify
                    (Mock.sortInjectionSubSubToTop Mock.plain00SubSubsort)
                    (Mock.sortInjectionSubToTop Mock.plain00Subsort)
            assertEqualWithExplanation "" expect actual
        , testCase "different head, subsort second" $ do
            let expect =
                    (   [ Conditional
                            { term =
                                Mock.sortInjectionSubToTop
                                    (mkAnd
                                        Mock.plain00Subsort
                                        (Mock.sortInjectionSubSubToSub
                                            Mock.plain00SubSubsort
                                        )
                                    )
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                        ]
                    , Nothing
                    )
            actual <-
                simplifyUnify
                    (Mock.sortInjectionSubToTop Mock.plain00Subsort)
                    (Mock.sortInjectionSubSubToTop Mock.plain00SubSubsort)
            assertEqualWithExplanation "" expect actual
        , testCase "different head constructors not subsort" $ do
            let expect = ([], Just [])
            actual <-
                simplifyUnify
                    (Mock.sortInjection10 Mock.aSort0)
                    (Mock.sortInjection11 Mock.aSort1)
            assertEqualWithExplanation "" expect actual
        , testCase "different head constructors subsort" $ do
            let expect = ([], Just [])
            actual <-
                simplifyUnify
                    (Mock.sortInjectionSubToTop Mock.aSubsort)
                    (Mock.sortInjectionSubSubToTop Mock.aSubSubsort)
            assertEqualWithExplanation "" expect actual
        , testCase "different head constructors common subsort" $ do
            let expect = ([], Just [])
            actual <-
                simplifyUnify
                    (Mock.sortInjectionOtherToTop Mock.aOtherSort)
                    (Mock.sortInjectionSubToTop Mock.aSubsort)
            assertEqualWithExplanation "" expect actual
        , testCase "different head constructors common subsort reversed" $ do
            let expect = ([], Just [])
            actual <-
                simplifyUnify
                    (Mock.sortInjectionSubToTop Mock.aSubsort)
                    (Mock.sortInjectionOtherToTop Mock.aOtherSort)
            assertEqualWithExplanation "" expect actual
        ]

    , testGroup "constructor and"
        [ testCase "same head" $ do
            let expect =
                    let
                        expected = Conditional
                            { term = Mock.constr10 Mock.cf
                            , predicate = makeEqualsPredicate Mock.cf Mock.cg
                            , substitution = mempty
                            }
                    in ([expected], Just [expected])
            actual <-
                simplifyUnify
                    (Mock.constr10 Mock.cf)
                    (Mock.constr10 Mock.cg)
            assertEqualWithExplanation "" expect actual

        , testCase "same head same child" $ do
            let expect =
                    let
                        expected = Conditional
                            { term = Mock.constr10 Mock.cf
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                    in ([expected], Just [expected])
            actual <-
                simplifyUnify
                    (Mock.constr10 Mock.cf)
                    (Mock.constr10 Mock.cf)
            assertEqualWithExplanation "" expect actual

        , testCase "different head" $ do
            let expect = ([], Just [])
            actual <-
                simplifyUnify
                    (Mock.constr10 Mock.cf)
                    (Mock.constr11 Mock.cf)
            assertEqualWithExplanation "" expect actual
        ]

    , testCase "constructor-sortinjection and" $ do
        let expect = ([], Just [])
        actual <-
            simplifyUnify
                (Mock.constr10 Mock.cf)
                (Mock.sortInjection11 Mock.cfSort1)
        assertEqualWithExplanation "" expect actual

    , testGroup "domain value and"
        [ testCase "equal values" $ do
            let expect =
                    let
                        expected = Conditional
                            { term = aDomainValue
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                    in ([expected], Just [expected])
            actual <- simplifyUnify aDomainValue aDomainValue
            assertEqualWithExplanation "" expect actual

        , testCase "different values" $ do
            let expect = ([], Just [])
            actual <- simplifyUnify aDomainValue bDomainValue
            assertEqualWithExplanation "" expect actual
        ]

    , testGroup "string literal and"
        [ testCase "equal values" $ do
            let expect =
                    let
                        expected = Conditional
                            { term = mkStringLiteral "a"
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                    in ([expected], Just [expected])
            actual <-
                simplifyUnify
                    (mkStringLiteral "a")
                    (mkStringLiteral "a")
            assertEqualWithExplanation "" expect actual

        , testCase "different values" $ do
            let expect = ([], Just [])
            actual <-
                simplifyUnify
                    (mkStringLiteral "a")
                    (mkStringLiteral "b")
            assertEqualWithExplanation "" expect actual
        ]

    , testGroup "char literal and"
        [ testCase "equal values" $ do
            let expect =
                    let
                        expected = Conditional
                            { term = mkCharLiteral 'a'
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                    in ([expected], Just [expected])
            actual <- simplifyUnify (mkCharLiteral 'a') (mkCharLiteral 'a')
            assertEqualWithExplanation "" expect actual

        , testCase "different values" $ do
            let expect = ([], Just [])
            actual <- simplifyUnify (mkCharLiteral 'a') (mkCharLiteral 'b')
            assertEqualWithExplanation "" expect actual
        ]

    , testGroup "function and"
        [ testCase "equal values" $ do
            let expect =
                    let
                        expanded = Conditional
                            { term = fOfA
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                    in ([expanded], Just [expanded])
            actual <- simplifyUnify fOfA fOfA
            assertEqualWithExplanation "" expect actual

        , testCase "not equal values" $ do
            let expect =
                    let
                        expanded = Conditional
                            { term = fOfA
                            , predicate = makeEqualsPredicate fOfA gOfA
                            , substitution = mempty
                            }
                    in ([expanded], Just [expanded])
            actual <- simplifyUnify fOfA gOfA
            assertEqualWithExplanation "" expect actual
        ]

    , testGroup "unhandled cases"
        [ testCase "top level" $ do
            let expect =
                    (   [ Conditional
                            { term = mkAnd plain0OfA plain1OfA
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                        ]
                    , Nothing
                    )
            actual <- simplifyUnify plain0OfA plain1OfA
            assertEqualWithExplanation "" expect actual

        , testCase "one level deep" $ do
            let expect =
                    (   [ Conditional
                            { term = Mock.constr10 (mkAnd plain0OfA plain1OfA)
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                        ]
                    , Nothing
                    )
            actual <-
                simplifyUnify
                    (Mock.constr10 plain0OfA) (Mock.constr10 plain1OfA)
            assertEqualWithExplanation "" expect actual

        , testCase "two levels deep" $ do
            let expect =
                    (   [ Conditional
                            { term =
                                Mock.constr10
                                    (Mock.constr10 (mkAnd plain0OfA plain1OfA))
                            , predicate = makeTruePredicate
                            , substitution = mempty
                            }
                        ]
                    , Nothing
                    )
            actual <-
                simplifyUnify
                    (Mock.constr10 (Mock.constr10 plain0OfA))
                    (Mock.constr10 (Mock.constr10 plain1OfA))
            assertEqualWithExplanation "" expect actual
        ]

    , testCase "binary constructor of non-specialcased values" $ do
        let expect =
                (   [ Conditional
                        { term =
                            Mock.functionalConstr20
                                (mkAnd plain0OfA plain1OfA)
                                (mkAnd plain0OfB plain1OfB)
                        , predicate = makeTruePredicate
                        , substitution = mempty
                        }
                    ]
                , Nothing
                )
        actual <-
            simplifyUnify
                (Mock.functionalConstr20 plain0OfA plain0OfB)
                (Mock.functionalConstr20 plain1OfA plain1OfB)
        assertEqualWithExplanation "" expect actual

    , testGroup "builtin Map domain"
        [ testCase "concrete Map, same keys" $ do
            let expect = Just
                    [ Conditional
                        { term = Mock.builtinMap [(Mock.aConcrete, Mock.b)]
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap [(Mock.x, Mock.b)]
                        }
                    ]
            actual <-
                unify
                    (Mock.builtinMap [(Mock.aConcrete, Mock.b)])
                    (Mock.builtinMap [(Mock.aConcrete, mkVar Mock.x)])
            assertEqualWithExplanation "" expect actual

        , testCase "concrete Map, different keys" $ do
            let expect = Just []
            actual <-
                unify
                    (Mock.builtinMap [(Mock.aConcrete, Mock.b)])
                    (Mock.builtinMap [(Mock.bConcrete, mkVar Mock.x)])
            assertEqualWithExplanation "" expect actual

        , testCase "concrete Map with framed Map" $ do
            let expect = Just
                    [ Conditional
                        { term =
                            Mock.builtinMap
                                [ (Mock.aConcrete, fOfA)
                                , (Mock.bConcrete, fOfB)
                                ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.wrap
                            [ (Mock.x, fOfA)
                            , (Mock.m, Mock.builtinMap [(Mock.bConcrete, fOfB)])
                            ]
                        }
                    ]
            actual <-
                unify
                    (Mock.builtinMap
                        [ (Mock.aConcrete, fOfA)
                        , (Mock.bConcrete, fOfB)
                        ]
                    )
                    (Mock.concatMap
                        (Mock.builtinMap [(Mock.aConcrete, mkVar Mock.x)])
                        (mkVar Mock.m)
                    )
            assertEqualWithExplanation "" expect actual

        , testCase "concrete Map with framed Map" $ do
            let expect = Just
                    [ Conditional
                        { term =
                            Mock.builtinMap
                                [ (Mock.aConcrete, fOfA)
                                , (Mock.bConcrete, fOfB)
                                ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.wrap
                            [ (Mock.x, fOfA)
                            , (Mock.m, Mock.builtinMap [(Mock.bConcrete, fOfB)])
                            ]
                        }
                    ]
            actual <-
                unify
                    (Mock.builtinMap
                        [ (Mock.aConcrete, fOfA)
                        , (Mock.bConcrete, fOfB)
                        ]
                    )
                    (Mock.concatMap
                        (mkVar Mock.m)
                        (Mock.builtinMap [(Mock.aConcrete, mkVar Mock.x)])
                    )
            assertEqualWithExplanation "" expect actual

        , testCase "framed Map with concrete Map" $ do
            let expect = Just
                    [ Conditional
                        { term =
                            Mock.builtinMap
                                [ (Mock.aConcrete, fOfA)
                                , (Mock.bConcrete, fOfB)
                                ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.wrap
                            [ (Mock.x, fOfA)
                            , (Mock.m, Mock.builtinMap [(Mock.bConcrete, fOfB)])
                            ]
                        }
                    ]
            actual <-
                unify
                    (Mock.concatMap
                        (Mock.builtinMap [(Mock.aConcrete, mkVar Mock.x)])
                        (mkVar Mock.m)
                    )
                    (Mock.builtinMap
                        [ (Mock.aConcrete, fOfA)
                        , (Mock.bConcrete, fOfB)
                        ]
                    )
            assertEqualWithExplanation "" expect actual

        , testCase "framed Map with concrete Map" $ do
            let expect = Just
                    [ Conditional
                        { term =
                            Mock.builtinMap
                                [ (Mock.aConcrete, fOfA)
                                , (Mock.bConcrete, fOfB)
                                ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.wrap
                            [ (Mock.x, fOfA)
                            , (Mock.m, Mock.builtinMap [(Mock.bConcrete, fOfB)])
                            ]
                        }
                    ]
            actual <-
                unify
                    (Mock.concatMap
                        (mkVar Mock.m)
                        (Mock.builtinMap [(Mock.aConcrete, mkVar Mock.x)])
                    )
                    (Mock.builtinMap
                        [ (Mock.aConcrete, fOfA)
                        , (Mock.bConcrete, fOfB)
                        ]
                    )
            assertEqualWithExplanation "" expect actual

        , testCase "concrete Map with element+unit" $ do
            let expect = Just
                    [ Conditional
                        { term = Mock.builtinMap [ (Mock.aConcrete, fOfA) ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.wrap
                            [ (Mock.x, Mock.a)
                            , (Mock.y, fOfA)
                            ]
                        }
                    ]
            actual <-
                unify
                    (Mock.builtinMap [ (Mock.aConcrete, fOfA) ])
                    (Mock.concatMap
                        (Mock.elementMap (mkVar Mock.x) (mkVar Mock.y))
                        Mock.unitMap
                    )
            assertEqualWithExplanation "" expect actual
        , testCase "map elem key inj splitting" $ do
            let
                expected = Just
                    [ Conditional
                        { term = Mock.builtinMap
                            [   ( Mock.sortInjection Mock.testSort
                                    $ Mock.sortInjectionSubSubToSub
                                        Mock.aSubSubsort
                                , fOfA
                                )
                            ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [   ( Mock.xSubSort
                                , Mock.sortInjectionSubSubToSub Mock.aSubSubsort
                                )
                            ,   ( Mock.y, fOfA )
                            ]
                        }
                    ]
            actual <- unify
                (Mock.builtinMap
                    [   ( Mock.sortInjection Mock.testSort Mock.aSubSubsort
                        , fOfA
                        )
                    ]
                )
                (Mock.elementMap
                    (Mock.sortInjection Mock.testSort (mkVar Mock.xSubSort))
                    (mkVar Mock.y)
                )
            assertEqualWithExplanation "" expected actual
        , testCase "map elem value inj splitting" $ do
            let
                key = Mock.a
                value = Mock.sortInjection Mock.testSort Mock.aSubSubsort
                testMap = Mock.builtinMap [(key, value)]
                valueInj =
                    Mock.sortInjection Mock.testSort
                    $ Mock.sortInjection Mock.subSort Mock.aSubSubsort
                testMapInj = Mock.builtinMap [(key, valueInj)]
                expected = Just
                    [ Conditional
                        { term = testMapInj
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [   ( Mock.xSubSort
                                , Mock.sortInjection
                                    Mock.subSort
                                    Mock.aSubSubsort
                                )
                            ,   ( Mock.y, Mock.a )
                            ]
                        }
                    ]
            actual <- unify
                testMap
                (Mock.elementMap
                    (mkVar Mock.y)
                    (Mock.sortInjection Mock.testSort (mkVar Mock.xSubSort))
                )
            assertEqualWithExplanation "" expected actual
        , testCase "map concat key inj splitting" $ do
            let
                expected = Just
                    [ Conditional
                        { term = Mock.builtinMap
                            [   ( Mock.sortInjection Mock.testSort
                                    (Mock.sortInjectionSubSubToSub
                                        Mock.aSubSubsort
                                    )
                                , fOfA
                                )
                            ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [   ( Mock.xSubSort
                                , Mock.sortInjectionSubSubToSub Mock.aSubSubsort
                                )
                            ,   ( Mock.y, fOfA )
                            ,   ( Mock.m, Mock.builtinMap [])
                            ]
                        }
                    ]
            actual <- unify
                (Mock.builtinMap
                    [   ( Mock.sortInjection Mock.testSort Mock.aSubSubsort
                        , fOfA
                        )
                    ]
                )
                (Mock.concatMap
                    (Mock.elementMap
                        (Mock.sortInjection Mock.testSort (mkVar Mock.xSubSort))
                        (mkVar Mock.y)
                    )
                    (mkVar Mock.m)
                )
            assertEqualWithExplanation "" expected actual
        , testCase "map elem value inj splitting" $ do
            let
                expected = Just
                    [ Conditional
                        { term = Mock.builtinMap
                            [   ( Mock.a
                                , Mock.sortInjection Mock.testSort
                                    (Mock.sortInjectionSubSubToSub
                                        Mock.aSubSubsort
                                    )
                                )
                            ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [   ( Mock.xSubSort
                                , Mock.sortInjectionSubSubToSub Mock.aSubSubsort
                                )
                            ,   ( Mock.y, Mock.a )
                            ,   ( Mock.m, Mock.builtinMap [])
                            ]
                        }
                    ]
            actual <- unify
                (Mock.builtinMap
                    [ (Mock.a, Mock.sortInjection Mock.testSort Mock.aSubSubsort) ]
                )
                (Mock.concatMap
                    (Mock.elementMap
                        (mkVar Mock.y)
                        (Mock.sortInjection Mock.testSort (mkVar Mock.xSubSort))
                    )
                    (mkVar Mock.m)
                )
            assertEqualWithExplanation "" expected actual
        -- TODO: Add tests with non-trivial predicates.
        ]

    , testGroup "builtin List domain"
        [ testCase "[same head, same head]" $ do
            let term1 =
                    Mock.builtinList
                        [ Mock.constr10 Mock.cf
                        , Mock.constr11 Mock.cf
                        ]
                expect = Just
                    [ Conditional
                        { term = term1
                        , predicate = makeTruePredicate
                        , substitution = mempty
                        }
                    ]
            actual <- unify term1 term1
            assertEqualWithExplanation "" expect actual

        , testCase "[same head, different head]" $ do
            let term3 = Mock.builtinList [Mock.a, Mock.a]
                term4 = Mock.builtinList [Mock.a, Mock.b]
                expect = Just []
            actual <- unify term3 term4
            assertEqualWithExplanation "" expect actual

        , testCase "[a] `concat` x /\\ [a, b] " $ do
            let x = varS "x" Mock.listSort
                term5 =
                    Mock.concatList (Mock.builtinList [Mock.a]) (mkVar $ x)
                term6 = Mock.builtinList [Mock.a, Mock.b]
                expect = Just
                    [ Conditional
                        { term = Mock.builtinList [Mock.a, Mock.b]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [(x, Mock.builtinList [Mock.b])]
                        }
                    ]
            actual <- unify term5 term6
            assertEqualWithExplanation "" expect actual

        , testCase "different lengths" $ do
            let term7 = Mock.builtinList [Mock.a, Mock.a]
                term8 = Mock.builtinList [Mock.a]
                expect = Just [Pattern.bottom]
            actual <- unify term7 term8
            assertEqualWithExplanation "" expect actual

        -- TODO: Add tests with non-trivial unifications and predicates.
        ]

    , testGroup "Builtin Set domain"
        [ testCase "set singleton + unit" $ do
            let
                expected = Just
                    [ Conditional
                        { term = Mock.builtinSet [Mock.a]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [ (Mock.x, Mock.a) ]
                        }
                    ]
            actual <- unify
                (Mock.concatSet
                    (Mock.elementSet (mkVar Mock.x))
                    Mock.unitSet
                )
                (Mock.builtinSet [Mock.a])
            assertEqualWithExplanation "" expected actual
        ,  testCase "handles set ambiguity" $ do
            let
                expected1 =
                    Conditional
                        { term = Mock.builtinSet [Mock.a, Mock.b]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [ (Mock.x, Mock.a)
                            , (Mock.xSet, Mock.builtinSet [Mock.b])
                            ]
                        }
                expected2 =
                    Conditional
                        { term = Mock.builtinSet [Mock.a, Mock.b]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [ (Mock.x, Mock.b)
                            , (Mock.xSet, Mock.builtinSet [Mock.a])
                            ]
                        }
            actual <- unify
                (Mock.concatSet
                    (Mock.elementSet (mkVar Mock.x))
                    (mkVar Mock.xSet)
                )
                (Mock.builtinSet [Mock.a, Mock.b])
            assertEqualWithExplanation "" (Just [expected1, expected2]) actual
        , testCase "set elem inj splitting" $ do
            let
                expected = Just
                    [ Conditional
                        { term = Mock.builtinSet
                            [ Mock.sortInjection Mock.testSort Mock.aSubSubsort ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [   ( Mock.xSubSort
                                , Mock.sortInjectionSubSubToSub Mock.aSubSubsort
                                )
                            ]
                        }
                    ]
            actual <- unify
                (Mock.elementSet
                    (Mock.sortInjection Mock.testSort (mkVar Mock.xSubSort))
                )
                (Mock.builtinSet
                    [Mock.sortInjection Mock.testSort Mock.aSubSubsort]
                )
            assertEqualWithExplanation "" expected actual
        , testCase "set concat inj splitting" $ do
            let
                expected = Just
                    [ Conditional
                        { term = Mock.builtinSet
                            [ Mock.sortInjection Mock.testSort Mock.aSubSubsort ]
                        , predicate = makeTruePredicate
                        , substitution = Substitution.unsafeWrap
                            [   ( Mock.xSubSort
                                , Mock.sortInjectionSubSubToSub Mock.aSubSubsort
                                )
                            ,   ( Mock.xSet
                                , Mock.builtinSet []
                                )
                            ]
                        }
                    ]
            actual <- unify
                (Mock.concatSet
                    (Mock.elementSet
                        (Mock.sortInjection Mock.testSort (mkVar Mock.xSubSort))
                    )
                    (mkVar Mock.xSet)
                )
                (Mock.builtinSet
                    [Mock.sortInjection Mock.testSort Mock.aSubSubsort]
                )
            assertEqualWithExplanation "" expected actual
        , testCase "set concat 2 inj splitting" $ do
            let
                testSet =
                    Mock.builtinSet
                        [ Mock.a
                        , Mock.sortInjection Mock.testSort Mock.aSubSubsort
                        ]
                expected =
                    [ Conditional
                            { term = testSet
                            , predicate = makeTruePredicate
                            , substitution = Substitution.unsafeWrap
                                [   (Mock.x, Mock.a)
                                ,   ( Mock.xSubSort
                                    , Mock.sortInjectionSubSubToSub
                                        Mock.aSubSubsort
                                    )
                                ,   (Mock.xSet, Mock.builtinSet [])
                                ]
                            }
                    ]
            actual <- unify
                (Mock.concatSet
                    (Mock.elementSet (mkVar Mock.x))
                    (Mock.concatSet
                        (Mock.elementSet
                            (Mock.sortInjection
                                Mock.testSort
                                (mkVar Mock.xSubSort)
                            )
                        )
                        (mkVar Mock.xSet)
                    )
                )
                testSet
            assertEqualWithExplanation "" (Just expected) actual
        ]
    ]

test_equalsTermsSimplification :: [TestTree]
test_equalsTermsSimplification =
    [ testCase "adds ceil when producing substitutions" $ do
        let expected = Just
                [ Conditional
                    { term = ()
                    , predicate = makeCeilPredicate Mock.cf
                    , substitution = Substitution.unsafeWrap [(Mock.x, Mock.cf)]
                    }
                ]
        actual <- simplifyEquals Map.empty (mkVar Mock.x) Mock.cf
        assertEqualWithExplanation "" expected actual
    , testCase "handles ambiguity" $ do
        let
            expected = Just
                [ Conditional
                    { term = ()
                    , predicate = makeEqualsPredicate (Mock.f Mock.a) Mock.a
                    , substitution = Substitution.unsafeWrap [(Mock.x, Mock.cf)]
                    }
                , Conditional
                    { term = ()
                    , predicate = makeEqualsPredicate (Mock.f Mock.b) Mock.b
                    , substitution = Substitution.unsafeWrap [(Mock.x, Mock.cf)]
                    }
                ]
            sortVar = SortVariableSort (SortVariable (testId "S"))
            simplifiers = axiomPatternsToEvaluators $ Map.fromList
                [   (   AxiomIdentifier.Ceil
                            (AxiomIdentifier.Application Mock.cfId)
                    ,   [ EqualityRule RulePattern
                            { left = mkCeil sortVar Mock.cf
                            , right =
                                mkOr
                                    (mkAnd
                                        (mkEquals_
                                            (Mock.f (mkVar Mock.y))
                                            Mock.a
                                        )
                                        (mkEquals_ (mkVar Mock.y) Mock.a)
                                    )
                                    (mkAnd
                                        (mkEquals_
                                            (Mock.f (mkVar Mock.y))
                                            Mock.b
                                        )
                                        (mkEquals_ (mkVar Mock.y) Mock.b)
                                    )
                            , requires = makeTruePredicate
                            , ensures = makeTruePredicate
                            , attributes = def
                                {Attribute.simplification = Simplification True}
                            }
                        ]
                    )
                ]
        actual <- simplifyEquals simplifiers (mkVar Mock.x) Mock.cf
        assertEqualWithExplanation "" expected actual
    , testCase "handles multiple ambiguity" $ do
        let
            expected = Just
                [ Conditional
                    { term = ()
                    , predicate = makeAndPredicate
                        (makeEqualsPredicate (Mock.f Mock.a) Mock.a)
                        (makeEqualsPredicate (Mock.g Mock.a) Mock.a)
                    , substitution = Substitution.unsafeWrap
                        [ (Mock.x, Mock.cf), (Mock.var_x_1, Mock.cg) ]
                    }
                , Conditional
                    { term = ()
                    , predicate = makeAndPredicate
                        (makeEqualsPredicate (Mock.f Mock.a) Mock.a)
                        (makeEqualsPredicate (Mock.g Mock.b) Mock.b)
                    , substitution = Substitution.unsafeWrap
                        [ (Mock.x, Mock.cf), (Mock.var_x_1, Mock.cg) ]
                    }
                , Conditional
                    { term = ()
                    , predicate = makeAndPredicate
                        (makeEqualsPredicate (Mock.f Mock.b) Mock.b)
                        (makeEqualsPredicate (Mock.g Mock.a) Mock.a)
                    , substitution = Substitution.unsafeWrap
                        [ (Mock.x, Mock.cf), (Mock.var_x_1, Mock.cg) ]
                    }
                , Conditional
                    { term = ()
                    , predicate = makeAndPredicate
                        (makeEqualsPredicate (Mock.f Mock.b) Mock.b)
                        (makeEqualsPredicate (Mock.g Mock.b) Mock.b)
                    , substitution = Substitution.unsafeWrap
                        [ (Mock.x, Mock.cf), (Mock.var_x_1, Mock.cg) ]
                    }
                ]
            sortVar = SortVariableSort (SortVariable (testId "S"))
            simplifiers = axiomPatternsToEvaluators $ Map.fromList
                [   (   AxiomIdentifier.Ceil
                            (AxiomIdentifier.Application Mock.cfId)
                    ,   [ EqualityRule RulePattern
                            { left = mkCeil sortVar Mock.cf
                            , right =
                                mkOr
                                    (mkAnd
                                        (mkEquals_
                                            (Mock.f (mkVar Mock.y))
                                            Mock.a
                                        )
                                        (mkEquals_ (mkVar Mock.y) Mock.a)
                                    )
                                    (mkAnd
                                        (mkEquals_
                                            (Mock.f (mkVar Mock.y))
                                            Mock.b
                                        )
                                        (mkEquals_ (mkVar Mock.y) Mock.b)
                                    )
                            , requires = makeTruePredicate
                            , ensures = makeTruePredicate
                            , attributes = def
                                {Attribute.simplification = Simplification True}
                            }
                        ]
                    )
                ,   (   AxiomIdentifier.Ceil
                            (AxiomIdentifier.Application Mock.cgId)
                    ,   [ EqualityRule RulePattern
                            { left = mkCeil sortVar Mock.cg
                            , right =
                                mkOr
                                    (mkAnd
                                        (mkEquals_
                                            (Mock.g (mkVar Mock.z))
                                            Mock.a
                                        )
                                        (mkEquals_ (mkVar Mock.z) Mock.a)
                                    )
                                    (mkAnd
                                        (mkEquals_
                                            (Mock.g (mkVar Mock.z))
                                            Mock.b
                                        )
                                        (mkEquals_ (mkVar Mock.z) Mock.b)
                                    )
                            , requires = makeTruePredicate
                            , ensures = makeTruePredicate
                            , attributes = def
                                {Attribute.simplification = Simplification True}
                            }
                        ]
                    )
                ]
        actual <- simplifyEquals
            simplifiers
            (Mock.functionalConstr20 (mkVar Mock.x) (mkVar Mock.var_x_1))
            (Mock.functionalConstr20 Mock.cf Mock.cg)
        assertEqualWithExplanation "" expected actual
    , testCase "handles set ambiguity" $ do
        let
            asInternal = Set.asInternal Mock.metadataTools Mock.setSort
            expected = Just $ do -- list monad
                (xValue, xSetValue) <-
                    [ (Mock.a, [Mock.b])
                    , (Mock.b, [Mock.a])
                    ]
                return Conditional
                    { term = ()
                    , predicate = makeTruePredicate
                    , substitution = Substitution.unsafeWrap
                        [ (Mock.x, xValue)
                        , (Mock.xSet, asInternal (Set.fromList xSetValue))
                        ]
                    }
        actual <- simplifyEquals
            Map.empty
            (Mock.concatSet (Mock.elementSet (mkVar Mock.x)) (mkVar Mock.xSet))
            (asInternal (Set.fromList [Mock.a, Mock.b]))
        assertEqualWithExplanation "" expected actual
    ]

fOfA :: TermLike Variable
fOfA = Mock.f Mock.a

fOfB :: TermLike Variable
fOfB = Mock.f Mock.b

gOfA :: TermLike Variable
gOfA = Mock.g Mock.a

plain0OfA :: TermLike Variable
plain0OfA = Mock.plain10 Mock.a

plain1OfA :: TermLike Variable
plain1OfA = Mock.plain11 Mock.a

plain0OfB :: TermLike Variable
plain0OfB = Mock.plain10 Mock.b

plain1OfB :: TermLike Variable
plain1OfB = Mock.plain11 Mock.b

aDomainValue :: TermLike Variable
aDomainValue =
    mkDomainValue DomainValue
        { domainValueSort = Mock.testSort
        , domainValueChild = mkStringLiteral "a"
        }

bDomainValue :: TermLike Variable
bDomainValue =
    mkDomainValue DomainValue
        { domainValueSort = Mock.testSort
        , domainValueChild = mkStringLiteral "b"
        }

simplifyUnify
    :: TermLike Variable
    -> TermLike Variable
    -> IO ([Pattern Variable], Maybe [Pattern Variable])
simplifyUnify first second =
    (,)
        <$> simplify first second
        <*> unify first second

unify
    :: TermLike Variable
    -> TermLike Variable
    -> IO (Maybe [Pattern Variable])
unify first second =
    SMT.runSMT SMT.defaultConfig emptyLogger
    $ evalSimplifier mockEnv
    $ runMaybeT unification
  where
    mockEnv = Mock.env
    unification =
        -- The unification error is discarded because, for testing purposes, we
        -- are not interested in the /reason/ unification failed. For the tests,
        -- the failure is almost always due to unsupported patterns anyway.
        MaybeT . fmap Error.hush . Monad.Unify.runUnifierT
        $ termUnification first second

simplify
    :: TermLike Variable
    -> TermLike Variable
    -> IO [Pattern Variable]
simplify first second =
    SMT.runSMT SMT.defaultConfig emptyLogger
    $ evalSimplifier mockEnv
    $ BranchT.gather
    $ termAnd first second
  where
    mockEnv = Mock.env

simplifyEquals
    :: BuiltinAndAxiomSimplifierMap
    -> TermLike Variable
    -> TermLike Variable
    -> IO (Maybe [Predicate Variable])
simplifyEquals axiomIdToSimplifier first second =
    (fmap . fmap) MultiOr.extractPatterns
    $ SMT.runSMT SMT.defaultConfig emptyLogger
    $ evalSimplifier mockEnv
    $ runMaybeT $ termEquals first second
  where
    mockEnv = Mock.env { simplifierAxioms = axiomIdToSimplifier }
