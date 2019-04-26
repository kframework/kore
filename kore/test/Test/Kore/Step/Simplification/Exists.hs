module Test.Kore.Step.Simplification.Exists
    ( test_makeEvaluate
    , test_simplify
    ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Data.Map as Map

import           Kore.AST.Common
                 ( Exists (..) )
import           Kore.AST.Valid
import           Kore.Attribute.Symbol
                 ( StepperAttributes )
import           Kore.IndexedModule.MetadataTools
                 ( SmtMetadataTools )
import           Kore.Predicate.Predicate
                 ( makeCeilPredicate, makeEqualsPredicate, makeExistsPredicate,
                 makeTruePredicate )
import qualified Kore.Predicate.Predicate as Predicate
import           Kore.Sort
import           Kore.Step.Pattern as Pattern
import qualified Kore.Step.Representation.MultiOr as MultiOr
                 ( make )
import           Kore.Step.Representation.OrOfExpandedPattern
                 ( CommonOrOfExpandedPattern, OrOfExpandedPattern )
import           Kore.Step.Simplification.Data
                 ( evalSimplifier )
import qualified Kore.Step.Simplification.Exists as Exists
import qualified Kore.Step.Simplification.Simplifier as Simplifier
                 ( create )
import qualified Kore.Unification.Substitution as Substitution
import qualified SMT

import           Test.Kore
import           Test.Kore.Comparators ()
import qualified Test.Kore.IndexedModule.MockMetadataTools as Mock
                 ( makeMetadataTools )
import qualified Test.Kore.Step.MockSimplifiers as Mock
import qualified Test.Kore.Step.MockSymbols as Mock
import           Test.Tasty.HUnit.Extensions

test_simplify :: [TestTree]
test_simplify =
    [ [plain10, plain11] `simplifies` [plain10', plain11']            $ "\\or distribution"
    , [top]              `simplifies` [top]                           $ "\\top"
    , []                 `simplifies` []                              $ "\\bottom"
    , [equals]           `simplifies` [quantifyPredicate equals]      $ "\\equals"
    , [substForX]        `simplifies` [top]                           $ "discharge substitution"
    , [substOfX]         `simplifies` [quantifySubstitution substOfX] $ "substitution"
    ]
  where
    plain10 = pure $ Mock.plain10 (mkVar Mock.x)
    plain11 = pure $ Mock.plain11 (mkVar Mock.x)
    plain10' = mkExists Mock.x <$> plain10
    plain11' = mkExists Mock.x <$> plain11
    equals =
        (Pattern.topOf Mock.testSort)
            { predicate =
                Predicate.makeEqualsPredicate
                    (Mock.sigma (mkVar Mock.x) (mkVar Mock.z))
                    (Mock.sigma (mkVar Mock.y) (mkVar Mock.z))
            }
    quantifyPredicate predicated@Conditional { predicate } =
        predicated
            { predicate = Predicate.makeExistsPredicate Mock.x predicate }
    quantifySubstitution predicated@Conditional { predicate, substitution } =
        predicated
            { predicate =
                Predicate.makeAndPredicate predicate
                $ Predicate.makeExistsPredicate Mock.x
                $ Predicate.fromSubstitution substitution
            , substitution = mempty
            }
    substForX =
        (Pattern.topOf Mock.testSort)
            { substitution =
                Substitution.unsafeWrap
                    [(Mock.x, Mock.sigma (mkVar Mock.y) (mkVar Mock.z))]
            }
    substOfX =
        (Pattern.topOf Mock.testSort)
            { substitution =
                Substitution.unsafeWrap
                    [(Mock.y, Mock.sigma (mkVar Mock.x) (mkVar Mock.z))]
            }
    simplifies
        :: HasCallStack
        => [Pattern Object Variable]
        -> [Pattern Object Variable]
        -> String
        -> TestTree
    simplifies original expected message =
        testCase message $ do
            actual <- simplify mockMetadataTools (makeExists Mock.x original)
            assertEqualWithExplanation "expected simplification"
                (MultiOr.make expected) actual

test_makeEvaluate :: [TestTree]
test_makeEvaluate =
    [ testGroup "Exists - Predicates"
        [ testCase "Top" $ do
            let expect = MultiOr.make [ Pattern.top ]
            actual <-
                makeEvaluate mockMetadataTools
                    Mock.x
                    (Pattern.top :: Pattern Object Variable)
            assertEqualWithExplanation "" expect actual

        , testCase " Bottom" $ do
            let expect = MultiOr.make []
            actual <-
                makeEvaluate mockMetadataTools
                    Mock.x
                    (Pattern.bottom :: Pattern Object Variable)
            assertEqualWithExplanation "" expect actual
        ]

    , testCase "exists applies substitution if possible" $ do
        -- exists x . (t(x) and p(x) and [x = alpha, others])
        --    = t(alpha) and p(alpha) and [others]
        let expect =
                MultiOr.make
                    [ Conditional
                        { term = Mock.f gOfA
                        , predicate =
                            makeCeilPredicate (Mock.h gOfA)
                        , substitution = Substitution.unsafeWrap
                            [(Mock.y, fOfA)]
                        }
                    ]
        actual <-
            makeEvaluate mockMetadataTools
                Mock.x
                Conditional
                    { term = Mock.f (mkVar Mock.x)
                    , predicate = makeCeilPredicate (Mock.h (mkVar Mock.x))
                    , substitution =
                        Substitution.wrap [(Mock.x, gOfA), (Mock.y, fOfA)]
                    }
        assertEqualWithExplanation "exists with substitution" expect actual

    , testCase "exists disappears if variable not used" $ do
        -- exists x . (t and p and s)
        --    = t and p and s
        --    if t, p, s do not depend on x.
        let expect =
                MultiOr.make
                    [ Conditional
                        { term = fOfA
                        , predicate = makeCeilPredicate gOfA
                        , substitution = mempty
                        }
                    ]
        actual <-
            makeEvaluate mockMetadataTools
                Mock.x
                Conditional
                    { term = fOfA
                    , predicate = makeCeilPredicate gOfA
                    , substitution = mempty
                    }
        assertEqualWithExplanation "exists with substitution" expect actual

    , testCase "exists applied on term if not used elsewhere" $ do
        -- exists x . (t(x) and p and s)
        --    = (exists x . t(x)) and p and s
        --    if p, s do not depend on x.
        let expect =
                MultiOr.make
                    [ Conditional
                        { term = mkExists Mock.x fOfX
                        , predicate = makeCeilPredicate gOfA
                        , substitution = mempty
                        }
                    ]
        actual <-
            makeEvaluate mockMetadataTools
                Mock.x
                Conditional
                    { term = fOfX
                    , predicate = makeCeilPredicate gOfA
                    , substitution = mempty
                    }
        assertEqualWithExplanation "exists on term" expect actual

    , testCase "exists applied on predicate if not used elsewhere" $ do
        -- exists x . (t and p(x) and s)
        --    = t and (exists x . p(x)) and s
        --    if t, s do not depend on x.
        let expect =
                MultiOr.make
                    [ Conditional
                        { term = fOfA
                        , predicate =
                            makeExistsPredicate Mock.x (makeCeilPredicate fOfX)
                        , substitution = mempty
                        }
                    ]
        actual <-
            makeEvaluate mockMetadataTools
                Mock.x
                Conditional
                    { term = fOfA
                    , predicate = makeCeilPredicate fOfX
                    , substitution = mempty
                    }
        assertEqualWithExplanation "exists on predicate" expect actual

    , testCase "exists moves substitution above" $ do
        -- exists x . (t(x) and p(x) and s)
        --    = exists x . (t(x) and p(x)) and Top and s
        --    if s do not depend on x.
        let expect =
                MultiOr.make
                    [ Conditional
                        { term =
                            mkExists Mock.x (mkAnd fOfX (mkEquals_ fOfX gOfA))
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap [(Mock.y, hOfA)]
                        }
                    ]
        actual <-
            makeEvaluate mockMetadataTools
                Mock.x
                Conditional
                    { term = fOfX
                    , predicate = makeEqualsPredicate fOfX gOfA
                    , substitution = Substitution.wrap [(Mock.y, hOfA)]
                    }
        assertEqualWithExplanation "exists moves substitution" expect actual

    , testCase "exists reevaluates" $ do
        -- exists x . (top and (f(x) = f(g(a)) and [x=g(a)])
        --    = top.s
        let expect = MultiOr.make [ Pattern.top ]
        actual <-
            makeEvaluate mockMetadataTools
                Mock.x
                Conditional
                    { term = mkTop_
                    , predicate = makeEqualsPredicate fOfX (Mock.f gOfA)
                    , substitution = Substitution.wrap [(Mock.x, gOfA)]
                    }
        assertEqualWithExplanation "exists reevaluates" expect actual
    ]
  where
    fOfA = Mock.f Mock.a
    fOfX = Mock.f (mkVar Mock.x)
    gOfA = Mock.g Mock.a
    hOfA = Mock.h Mock.a

mockMetadataTools :: SmtMetadataTools StepperAttributes
mockMetadataTools =
    Mock.makeMetadataTools
        Mock.attributesMapping
        Mock.headTypeMapping
        Mock.sortAttributesMapping
        Mock.subsorts
        Mock.headSortsMapping
        Mock.smtDeclarations

makeExists
    :: Ord (variable Object)
    => variable Object
    -> [Pattern Object variable]
    -> Exists Object variable (OrOfExpandedPattern Object variable)
makeExists variable patterns =
    Exists
        { existsSort = testSort
        , existsVariable = variable
        , existsChild = MultiOr.make patterns
        }

testSort :: Sort Object
testSort =
    SortActualSort SortActual
        { sortActualName  = Id "testSort" AstLocationTest
        , sortActualSorts = []
        }

simplify
    :: MetaOrObject level
    => SmtMetadataTools StepperAttributes
    -> Exists level Variable (CommonOrOfExpandedPattern level)
    -> IO (CommonOrOfExpandedPattern level)
simplify tools exists =
    (<$>) fst
    $ SMT.runSMT SMT.defaultConfig
    $ evalSimplifier emptyLogger
    $ Exists.simplify
        tools
        (Mock.substitutionSimplifier tools)
        (Simplifier.create tools Map.empty)
        Map.empty
        exists

makeEvaluate
    :: MetaOrObject level
    => SmtMetadataTools StepperAttributes
    -> Variable level
    -> Pattern Object Variable
    -> IO (CommonOrOfExpandedPattern level)
makeEvaluate tools variable child =
    (<$>) fst
    $ SMT.runSMT SMT.defaultConfig
    $ evalSimplifier emptyLogger
    $ Exists.makeEvaluate
        tools
        (Mock.substitutionSimplifier tools)
        (Simplifier.create tools Map.empty)
        Map.empty
        variable
        child
