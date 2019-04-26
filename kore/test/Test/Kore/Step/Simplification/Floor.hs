module Test.Kore.Step.Simplification.Floor
    ( test_floorSimplification
    ) where

import Test.Tasty
       ( TestTree )
import Test.Tasty.HUnit
       ( testCase )

import           Kore.AST.Pure
import           Kore.AST.Valid
import           Kore.Predicate.Predicate
                 ( makeAndPredicate, makeEqualsPredicate, makeFloorPredicate,
                 makeTruePredicate )
import           Kore.Step.Representation.ExpandedPattern
                 ( CommonExpandedPattern, Conditional (..), ExpandedPattern )
import qualified Kore.Step.Representation.ExpandedPattern as ExpandedPattern
                 ( bottom, top )
import qualified Kore.Step.Representation.MultiOr as MultiOr
                 ( make )
import           Kore.Step.Representation.OrOfExpandedPattern
                 ( CommonOrOfExpandedPattern, OrOfExpandedPattern )
import           Kore.Step.Simplification.Floor
                 ( makeEvaluateFloor, simplify )
import           Kore.Step.TermLike
import qualified Kore.Unification.Substitution as Substitution

import Test.Kore
       ( testId )
import Test.Kore.Comparators ()
import Test.Kore.Step.MockSymbols
       ( testSort )
import Test.Tasty.HUnit.Extensions

test_floorSimplification :: [TestTree]
test_floorSimplification =
    [ testCase "Floor - or distribution"
        -- floor(a or b) = (top and floor(a)) or (top and floor(b))
        (assertEqualWithExplanation ""
            (MultiOr.make
                [ Conditional
                    { term = mkTop_
                    , predicate = makeFloorPredicate (mkOr a b)
                    , substitution = mempty
                    }
                ]
            )
            (evaluate
                (makeFloor
                    [aExpanded, bExpanded]
                )
            )
        )
    , testCase "Floor - bool operations"
        (do
            -- floor(top) = top
            assertEqualWithExplanation "floor(top)"
                (MultiOr.make
                    [ ExpandedPattern.top ]
                )
                (evaluate
                    (makeFloor
                        [ExpandedPattern.top]
                    )
                )
            -- floor(bottom) = bottom
            assertEqualWithExplanation "floor(bottom)"
                (MultiOr.make
                    []
                )
                (evaluate
                    (makeFloor
                        []
                    )
                )
        )
    , testCase "expanded Floor - bool operations"
        (do
            -- floor(top) = top
            assertEqualWithExplanation "floor(top)"
                (MultiOr.make
                    [ ExpandedPattern.top ]
                )
                (makeEvaluate
                    (ExpandedPattern.top :: CommonExpandedPattern Object)
                )
            -- floor(bottom) = bottom
            assertEqualWithExplanation "floor(bottom)"
                (MultiOr.make
                    []
                )
                (makeEvaluate
                    (ExpandedPattern.bottom :: CommonExpandedPattern Object)
                )
        )
    , testCase "floor with predicates and substitutions"
        -- floor(term and predicate and subst)
        --     = top and (floor(term) and predicate) and subst
        (assertEqualWithExplanation "floor(top)"
            (MultiOr.make
                [ Conditional
                    { term = mkTop_
                    , predicate =
                        makeAndPredicate
                            (makeFloorPredicate a)
                            (makeEqualsPredicate fOfA gOfA)
                    , substitution = Substitution.wrap [(x, fOfB)]
                    }
                ]
            )
            (makeEvaluate
                Conditional
                    { term = a
                    , predicate = makeEqualsPredicate fOfA gOfA
                    , substitution = Substitution.wrap [(x, fOfB)]
                    }
            )
        )
    -- floor moves predicates and substitutions up
    ]
  where
    fId = Id "f" AstLocationTest
    gId = Id "g" AstLocationTest
    aSymbol = SymbolOrAlias
        { symbolOrAliasConstructor = Id "a" AstLocationTest
        , symbolOrAliasParams      = []
        }
    bSymbol = SymbolOrAlias
        { symbolOrAliasConstructor = Id "b" AstLocationTest
        , symbolOrAliasParams      = []
        }
    fSymbol = SymbolOrAlias
        { symbolOrAliasConstructor = fId
        , symbolOrAliasParams      = []
        }
    gSymbol = SymbolOrAlias
        { symbolOrAliasConstructor = gId
        , symbolOrAliasParams      = []
        }
    x = Variable (testId "x") mempty testSort
    a :: TermLike Variable
    a = mkApp testSort aSymbol []
    b :: TermLike Variable
    b = mkApp testSort bSymbol []
    fOfA = mkApp testSort fSymbol [a]
    fOfB = mkApp testSort fSymbol [b]
    gOfA = mkApp testSort gSymbol [a]
    aExpanded = Conditional
        { term = a
        , predicate = makeTruePredicate
        , substitution = mempty
        }
    bExpanded = Conditional
        { term = b
        , predicate = makeTruePredicate
        , substitution = mempty
        }

makeFloor
    :: Ord (variable Object)
    => [ExpandedPattern Object variable]
    -> Floor Object (OrOfExpandedPattern Object variable)
makeFloor patterns =
    Floor
        { floorOperandSort = testSort
        , floorResultSort  = testSort
        , floorChild       = MultiOr.make patterns
        }

evaluate
    :: MetaOrObject level
    => Floor level (CommonOrOfExpandedPattern level)
    -> CommonOrOfExpandedPattern level
evaluate floor' =
    case simplify floor' of
        (result, _proof) -> result


makeEvaluate
    :: MetaOrObject level
    => CommonExpandedPattern level
    -> CommonOrOfExpandedPattern level
makeEvaluate child =
    case makeEvaluateFloor child of
        (result, _proof) -> result
