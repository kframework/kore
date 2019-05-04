{-# OPTIONS_GHC -Wno-missing-signatures #-}
{-# OPTIONS_GHC -Wno-missing-pattern-synonym-signatures #-}

module Test.Kore.AST.Valid
    ( test_sortAgreement
    ) where

import Test.Tasty
       ( TestTree, testGroup )
import Test.Tasty.HUnit
       ( assertEqual, testCase )

import Control.Lens
import Data.Text
       ( Text )

import Kore.AST.Lens
       ( resultSort )
import Kore.AST.Pure
import Kore.AST.Valid
import Kore.Step.TermLike
       ( TermLike )

test_sortAgreement :: TestTree
test_sortAgreement = testGroup "Sort agreement"
    [ testCase "sortAgreement1" $
        assertEqual ""
            (sortAgreement1 ^? inPath [1])
            (Just $ mkBottom (mkSort "X"))
    , testCase "sortAgreement2.1" $
        assertEqual ""
            (sortAgreement2 ^? inPath [0])
            (Just $ mkBottom (mkSort "Y"))
    , testCase "sortAgreement2.2" $
        assertEqual ""
            (sortAgreement2 ^? (inPath [1] . resultSort ))
            (Just $ mkSort "Y")
    , testCase "predicateSort.1" $
        assertEqual ""
            ((mkBottom_ :: TermLike Variable) ^? resultSort)
            (Just (predicateSort :: Sort))
    , testCase "predicateSort.2" $
        assertEqual ""
            ((mkTop_ :: TermLike Variable) ^? resultSort)
            (Just (predicateSort :: Sort))
    , testCase "predicateSort.3" $
        assertEqual ""
            ((mkExists (var_ "a" "A") mkBottom_
                    :: TermLike Variable) ^? resultSort)
            (Just (predicateSort :: Sort))
    , testGroup "sortAgreementManySimplePatterns"
        sortAgreementManySimplePatterns
    ]

-- the a : X forces bottom : X
sortAgreement1 :: TermLike Variable
sortAgreement1 =
    mkOr (mkVar $ var_ "a" "X") mkBottom_

-- the y : Y should force everything else to be Y
sortAgreement2 :: TermLike Variable
sortAgreement2 =
    mkImplies mkBottom_ $
    mkIff
        (mkEquals_ (mkVar $ var_ "foo" "X") (mkVar $ var_ "bar" "X"))
        (mkVar $ var_ "y" "Y")

varX :: TermLike Variable
varX = mkVar $ var_ "x" "X"

sortAgreementManySimplePatterns :: [TestTree]
sortAgreementManySimplePatterns = do
    flexibleZeroArg <- [mkBottom_, mkTop_]
    (a,b) <- [(varX, flexibleZeroArg), (flexibleZeroArg, varX), (varX, varX)]
    shouldHaveSortXOneArg <-
        [ mkForall (var "a") varX
        , mkExists (var "a") varX
        , mkNot varX
        , mkNext varX
        ]
    shouldHaveSortXTwoArgs <-
        [ mkAnd a b
        , mkOr a b
        , mkImplies a b
        , mkIff a b
        , mkRewrites a b
        ]
    shouldHavepredicateSortTwoArgs <-
        [ mkEquals_ a b
        , mkIn_ a b
        ]
    shoudlHavepredicateSortOneArg <-
        [ mkCeil_ a
        , mkFloor_ a
        ]
    let assert1 = return $ testCase "" $ assertEqual ""
            (getSort shouldHaveSortXOneArg)
            (mkSort "X")
    let assert2 = return $ testCase "" $ assertEqual ""
            (getSort shouldHaveSortXTwoArgs)
            (mkSort "X")
    let assert3 = return $ testCase "" $ assertEqual ""
            (getSort shoudlHavepredicateSortOneArg)
            predicateSort
    let assert4 = return $ testCase "" $ assertEqual ""
            (getSort shouldHavepredicateSortTwoArgs)
            predicateSort
    assert1 ++ assert2 ++ assert3 ++ assert4

var :: Text -> Variable
var x = Variable (noLocationId x) mempty (mkSort "S")

var_ :: Text -> Id -> Variable
var_ x s = Variable (noLocationId x) mempty (mkSort s)
