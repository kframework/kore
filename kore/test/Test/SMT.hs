module Test.SMT
    ( testPropertyWithSolver
    , testPropertyWithoutSolver
    , testCaseWithSMT
    , assertEqual'
    , runSMT
    , runNoSMT
    ) where

import Hedgehog
import Test.Tasty
import Test.Tasty.Hedgehog
import Test.Tasty.HUnit

import Control.Monad.IO.Class
import qualified Control.Monad.Morph as Morph
import qualified GHC.Stack as GHC

import SMT
    ( NoSMT
    , SMT
    )
import qualified SMT

testPropertyWithSolver
    :: GHC.HasCallStack
    => String
    -> PropertyT SMT ()
    -> TestTree
testPropertyWithSolver str =
    testProperty str . Hedgehog.property . Morph.hoist runSMT

testPropertyWithoutSolver
    :: GHC.HasCallStack
    => String
    -> PropertyT NoSMT ()
    -> TestTree
testPropertyWithoutSolver str =
    testProperty str . Hedgehog.property . Morph.hoist runNoSMT

testCaseWithSMT :: String -> SMT () -> TestTree
testCaseWithSMT str = testCase str . runSMT

assertEqual'
    :: MonadIO m
    => (Eq a, Show a)
    => GHC.HasCallStack
    => String  -- ^ Remark
    -> a  -- ^ Expected value
    -> a  -- ^ Actual value
    -> m ()
assertEqual' str expect = liftIO . assertEqual str expect

runSMT :: SMT a -> IO a
runSMT = SMT.runSMT SMT.defaultConfig mempty

runNoSMT :: NoSMT a -> IO a
runNoSMT = SMT.runNoSMT mempty
