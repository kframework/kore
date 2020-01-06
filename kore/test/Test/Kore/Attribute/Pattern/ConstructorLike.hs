module Test.Kore.Attribute.Pattern.ConstructorLike
    ( test_TermLike
    ) where

import Test.Tasty
import Test.Tasty.HUnit

import Kore.Internal.TermLike

import qualified Test.Kore.Step.MockSymbols as Mock

test_TermLike :: [TestTree]
test_TermLike =
    [ testCase "constructor-like BuiltinInt" $
        Mock.builtinInt 3 `shouldBeConstructorLike` True
    , testCase "constructor-like BuiltinBool" $
        Mock.builtinBool True `shouldBeConstructorLike` True
    , testCase "constructor-like BuiltinString" $
        Mock.builtinString "test" `shouldBeConstructorLike` True
    , testCase "constructor-like DomainValue" $
        domainValue `shouldBeConstructorLike` True
    , testCase "Simplifiable BuiltinSet" $
        Mock.builtinSet [] `shouldBeConstructorLike` True
    , testCase "Simplifiable BuiltinSet" $
        Mock.builtinSet [Mock.a, Mock.b] `shouldBeConstructorLike` True
    , testCase "Simplifiable BuiltinSet" $
        Mock.builtinSet [Mock.a, Mock.f Mock.b] `shouldBeConstructorLike` False
    , testCase "Simplifiable BuiltinMap" $
        Mock.builtinMap [] `shouldBeConstructorLike` True
    , testCase "Simplifiable BuiltinMap" $
        Mock.builtinMap [(Mock.a, Mock.c), (Mock.b, Mock.c)]
        `shouldBeConstructorLike` True
    , testCase "Simplifiable BuiltinMap" $
        Mock.builtinMap [(Mock.a, Mock.c), (Mock.f Mock.b, Mock.c)]
        `shouldBeConstructorLike` False
    , testCase "Single constructor is constructor-like" $
        Mock.a `shouldBeConstructorLike` True
    , testCase "constructor-like with constructor at the top" $
        Mock.constr10 (Mock.builtinInt 3) `shouldBeConstructorLike` True
    , testCase "Simplifiable pattern contains symbol which is only functional" $
        Mock.constr10 (Mock.f Mock.a) `shouldBeConstructorLike` False
    , testCase "constructor-like pattern with constructor and sort injection" $
        Mock.constr10
            ( Mock.sortInjection
                Mock.testSort
                (Mock.builtinInt 3)
            )
        `shouldBeConstructorLike` True
    , testCase "Two consecutive sort injections are simplifiable" $
        Mock.sortInjection
            Mock.intSort
            ( Mock.sortInjection
                Mock.testSort
                (Mock.builtinInt 3
                )
            )
        `shouldBeConstructorLike` False
    , testCase "constructor-like pattern with two non-consecutive sort injections" $
        Mock.sortInjection
            Mock.intSort
            ( Mock.constr10
                ( Mock.sortInjection
                    Mock.testSort
                    (Mock.builtinInt 3)
                )
            )
        `shouldBeConstructorLike` True
    ]
  where
    domainValue =
        mkDomainValue
            ( DomainValue
                Mock.testSort
                (mkStringLiteral "testDV")
            )

shouldBeConstructorLike
    :: TermLike Variable
    -> Bool
    -> IO ()
shouldBeConstructorLike term expected = do
    let actual = isConstructorLike term
    assertEqual "" actual expected
