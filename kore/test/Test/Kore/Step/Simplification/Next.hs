module Test.Kore.Step.Simplification.Next
    ( test_nextSimplification
    ) where

import Prelude.Kore

import Test.Tasty

import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeEqualsPredicate_
    , makeTruePredicate
    , makeTruePredicate_
    )
import Kore.Internal.TermLike
import Kore.Step.Simplification.Next
    ( simplify
    )

import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Tasty.HUnit.Ext

test_nextSimplification :: [TestTree]
test_nextSimplification =
    [ testCase "Next evaluates to Next"
        (assertEqual ""
            (OrPattern.fromPatterns
                [ Conditional
                    { term = mkNext Mock.a
                    , predicate = makeTruePredicate Mock.testSort
                    , substitution = mempty
                    }
                ]
            )
            (evaluate
                (makeNext
                    [ Conditional
                        { term = Mock.a
                        , predicate = makeTruePredicate_
                        , substitution = mempty
                        }
                    ]
                )
            )
        )
    , testCase "Next collapses or"
        (assertEqual ""
            (OrPattern.fromPatterns
                [ Conditional
                    { term =
                        mkNext
                            (mkOr
                                Mock.a
                                (mkAnd Mock.b (mkEquals_ Mock.a Mock.b))
                            )
                    , predicate = makeTruePredicate Mock.testSort
                    , substitution = mempty
                    }
                ]
            )
            (evaluate
                (makeNext
                    [ Conditional
                        { term = Mock.a
                        , predicate = makeTruePredicate_
                        , substitution = mempty
                        }
                    , Conditional
                        { term = Mock.b
                        , predicate = makeEqualsPredicate_ Mock.a Mock.b
                        , substitution = mempty
                        }
                    ]
                )
            )
        )
    ]

findSort :: [Pattern Variable] -> Sort
findSort [] = Mock.testSort
findSort ( Conditional {term} : _ ) = termLikeSort term

evaluate :: Next Sort (OrPattern Variable) -> OrPattern Variable
evaluate = simplify

makeNext
    :: [Pattern Variable]
    -> Next Sort (OrPattern Variable)
makeNext child =
    Next
        { nextSort = findSort child
        , nextChild = OrPattern.fromPatterns child
        }
