module Test.Kore.Step.Function.Memo where

import Test.Tasty
import Test.Tasty.HUnit

import Control.Monad.State.Strict
    ( evalState
    )

import Kore.Internal.TermLike
import Kore.Step.Function.Memo

import Test.Kore.Comparators ()
import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Tasty.HUnit.Extensions

test_Self :: [TestTree]
test_Self =
    [ testCase "simple - recall recorded result" $ do
        let Self { recall, record } = simple
            eval state = evalState state mempty
            recalled = eval $ do
                record key result
                recall key
        assertEqualWithExplanation "expected recorded result"
            (Just result)
            recalled
    , testCase "new - recall recorded result" $ do
        Self { recall, record } <- new
        record key result
        recalled <- recall key
        assertEqualWithExplanation "expected recorded result"
            (Just result)
            recalled
    ]
  where
    key =
        Application
            { applicationSymbolOrAlias = Mock.fSymbol
            , applicationChildren = [Mock.a]
            }
    result = Mock.b
