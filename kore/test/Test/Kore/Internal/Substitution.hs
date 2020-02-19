module Test.Kore.Internal.Substitution
    ( test_substitution
    , test_toPredicate
    ) where

import Prelude.Kore hiding
    ( null
    )

import Test.Tasty

import qualified Data.Set as Set

import Kore.Internal.Predicate
    ( Predicate
    , makeAndPredicate
    , makeEqualsPredicate_
    , makeTruePredicate_
    )
import Kore.Internal.Substitution
import Kore.Internal.TermLike hiding
    ( mapVariables
    )
import Kore.TopBottom
    ( isBottom
    , isTop
    )
import Kore.Variables.Target
    ( mkElementNonTarget
    , mkElementTarget
    )
import Kore.Variables.UnifiedVariable
    ( UnifiedVariable (..)
    )

import Test.Kore
import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Tasty.HUnit.Ext
import Test.Terse
    ( gives_
    )

test_substitution :: [TestTree]
test_substitution =
    [ monoidTests
    , unwrapTests
    , modifyTests
    , mapVariablesTests
    , isNormalizedTests
    , nullTests
    , variablesTests
    , propertyTests
    , orderRenameAndRenormalizeTODOTests
    ]

propertyTests:: TestTree
propertyTests =
  testGroup "the three notable kinds of `Substitution` values"
  [ isTop `gives_`        [(mempty, True),  (normalized, False), (unnormalized, False) ]
  , isBottom `gives_`     [(mempty, False), (normalized, False), (unnormalized, False) ]
  , isNormalized `gives_` [(mempty, True),  (normalized, True),  (unnormalized, False) ]
  , null `gives_`         [(mempty, True),  (normalized, False), (unnormalized, False) ]
  ]
  where
    normalized = unsafeWrap [(ElemVar Mock.x, Mock.a)]
    unnormalized = wrap [(ElemVar Mock.x, Mock.a)]


monoidTests:: TestTree
monoidTests =
    testGroup "Substitution.Monoid"
    [ testCase "empty <> empty == empty"
        $ assertEqual ""
            mempty
            $ wrap mempty <> wrap emptyRawSubst
    , testCase "empty <> normalized == normalized"
        $ assertEqual ""
            (unsafeWrap singletonSubst)
            $ wrap mempty <> unsafeWrap singletonSubst
    , testCase "empty normalized <> normalized == normalized"
        $ assertEqual ""
            (unsafeWrap singletonSubst)
            $ emptySubst <> unsafeWrap singletonSubst
    , testCase "normalized <> empty == normalized"
        $ assertEqual ""
            (unsafeWrap singletonSubst)
            $ unsafeWrap singletonSubst <> wrap mempty
    , testCase "normalized <> empty normalized == normalized"
        $ assertEqual ""
            (unsafeWrap singletonSubst)
            $ unsafeWrap singletonSubst <> emptySubst
    ]

unwrapTests :: TestTree
unwrapTests =
    testGroup "Substitution.unwrap"
    [ testCase "empty Substitution is empty"
        $ assertEqual ""
            mempty
            $ unwrap emptySubst
    , testCase "unwrap . wrap == id"
        $ assertEqual ""
            singletonSubst
            . unwrap . wrap
            $ singletonSubst
    , testCase "unwrap . unsafeWrap == id"
        $ assertEqual ""
            singletonSubst
            . unwrap . unsafeWrap
            $ singletonSubst
    ]

modifyTests :: TestTree
modifyTests =
    testGroup "Substitution.modify"
    [ testCase "modify id un-normalized == id"
        $ assertEqual ""
            (wrap singletonSubst)
            . modify id
            $ wrap singletonSubst
    , testCase "modify id normalized substitution un-normalizes"
        $ assertEqual ""
            (wrap singletonSubst)
            . modify id
            $ unsafeWrap singletonSubst
    , testCase "modify empty subst == id"
        $ assertEqual ""
            mempty
            . modify id
            $ emptySubst
    ]

mapVariablesTests :: TestTree
mapVariablesTests =
    testGroup "Substitution.mapVariables"
    [ testCase "map id over empty is empty"
        $ assertEqual ""
            (wrap mempty)
            . mapVariables id id $ emptySubst
    , testCase "map id over wrap empty is normalized empty"
        $ assertEqual ""
            (wrap mempty)
            . mapVariables id id $ wrap emptyRawSubst
    , testCase "map id over singleton == id"
        $ assertEqual ""
            (wrap singletonSubst)
            . mapVariables id id $ wrap singletonSubst
    , testCase "map id over normalized singletonSubst"
        $ assertEqual ""
            (wrap singletonSubst)
            . mapVariables id id $ unsafeWrap singletonSubst
    ]

isNormalizedTests :: TestTree
isNormalizedTests =
    testGroup "Substitution.isNormalized"
    [ testCase "mempty is normalized"
        $ assertEqual ""
            True
            . isNormalized $ emptySubst
    , testCase "wrap is not normalized"
        $ assertEqual ""
            False
            . isNormalized $ wrap singletonSubst
    , testCase "unsafeWrap is normalized"
        $ assertEqual ""
            True
            . isNormalized $ unsafeWrap singletonSubst
    ]

nullTests :: TestTree
nullTests =
    testGroup "Substitution.null"
    [ testCase "mempty is null"
        $ assertEqual ""
            True
            . null $ wrap emptyRawSubst
    , testCase "unsafeWrap empty is null"
        $ assertEqual ""
            True
            . null $ unsafeWrap emptyRawSubst
    , testCase "nonempty is not null"
        $ assertEqual ""
            False
            . null $ wrap singletonSubst
    , testCase "nonempty normalized is not null"
        $ assertEqual ""
            False
            . null $ unsafeWrap singletonSubst
    ]

variablesTests :: TestTree
variablesTests =
    testGroup "Substitution.variables"
    [ testCase "empty subst has no variables"
        $ assertEqual ""
            mempty
            $ variables emptySubst
    , testCase "empty wrapped subst has no variables"
        $ assertEqual ""
            mempty
            . variables $ wrap emptyRawSubst
    , testCase "singleton normalized subst has one variable"
        $ assertEqual ""
           (Set.fromList $ fst <$> singletonSubst)
           . variables $ unsafeWrap singletonSubst
    , testCase "singleton subst has one variable"
        $ assertEqual ""
           (Set.fromList $ fst <$> singletonSubst)
           . variables $ wrap singletonSubst
    ]

orderRenameAndRenormalizeTODOTests :: TestTree
orderRenameAndRenormalizeTODOTests =
    testGroup "Reverse RHS if equal to variable"
    [ testCase "empty subst unchanged"
        $ assertEqual ""
            emptySubst
            (orderRenameAndRenormalizeTODO (ElemVar Mock.x) emptySubst)
    , testCase "unnormalized without RHS unchanged" $ do
        let
            subst = wrap [(ElemVar Mock.x, Mock.a)]
        assertEqual ""
            subst
            (orderRenameAndRenormalizeTODO (ElemVar Mock.x) subst)
    , testCase "normalized without RHS unchanged" $ do
        let
            subst = unsafeWrap [(ElemVar Mock.x, Mock.a)]
        assertEqual ""
            subst
            (orderRenameAndRenormalizeTODO (ElemVar Mock.x) subst)
    , testCase "unnormalized reverses RHS" $ do
        let
            expectedSubst = wrap [(targetVarX, nonTargetPattY)]
            originalSubst = wrap [(nonTargetVarY, targetPattX)]
        assertEqual ""
            expectedSubst
            ( orderRenameAndRenormalizeTODO
                targetVarX
                originalSubst
            )
    , testCase "unnormalized does not reverse RHS" $ do
        let
            expectedSubst = wrap [(targetVarX, nonTargetPattY)]
            originalSubst = wrap [(targetVarX, nonTargetPattY)]
        assertEqual ""
            expectedSubst
            ( orderRenameAndRenormalizeTODO
                targetVarX
                originalSubst
            )
    , testCase "normalized reverses RHS" $ do
        let
            expectedSubst = unsafeWrap [(ElemVar Mock.x, mkElemVar Mock.y)]
            originalSubst = unsafeWrap [(ElemVar Mock.y, mkElemVar Mock.x)]
        assertEqual ""
            expectedSubst
            (orderRenameAndRenormalizeTODO (ElemVar Mock.x) originalSubst)
    , testCase "unnormalized reverses multiple RHS" $ do
        let
            expectedSubst = wrap
                [ (targetVarX, nonTargetPattY), (targetVarX, nonTargetPattZ) ]
            originalSubst = wrap
                [ (nonTargetVarY, targetPattX), (nonTargetVarZ, targetPattX) ]
        assertEqual ""
            expectedSubst
            (orderRenameAndRenormalizeTODO targetVarX originalSubst)
    , testCase "normalized reverses multiple RHS" $ do
        let
            expectedSubst = unsafeWrap
                [(ElemVar Mock.x, mkElemVar Mock.z), (ElemVar Mock.y, mkElemVar Mock.z)]
            originalSubst = unsafeWrap
                [(ElemVar Mock.y, mkElemVar Mock.x), (ElemVar Mock.z, mkElemVar Mock.x)]
        assertEqual ""
            expectedSubst
            (orderRenameAndRenormalizeTODO (ElemVar Mock.x) originalSubst)
    , testCase "unnormalized does not substitute reverse RHS" $ do
        let
            expectedSubst = wrap
                [ (ElemVar Mock.x, mkElemVar Mock.y)
                , (ElemVar Mock.z, Mock.f (mkElemVar Mock.x))
                ]
            originalSubst = wrap
                [ (ElemVar Mock.y, mkElemVar Mock.x)
                , (ElemVar Mock.z, Mock.f (mkElemVar Mock.x))
                ]
        assertEqual ""
            expectedSubst
            (orderRenameAndRenormalizeTODO (ElemVar Mock.x) originalSubst)
    , testCase "normalized substitutes reverse RHS" $ do
        let
            expectedSubst = unsafeWrap
                [ (ElemVar Mock.x, mkElemVar Mock.z)
                , (ElemVar Mock.y, mkElemVar Mock.z)
                , (ElemVar Mock.var_x_1, Mock.f (mkElemVar Mock.z))
                ]
            originalSubst = unsafeWrap
                [ (ElemVar Mock.y, mkElemVar Mock.x)
                , (ElemVar Mock.z, mkElemVar Mock.x)
                , (ElemVar Mock.var_x_1, Mock.f (mkElemVar Mock.x))
                ]
        assertEqual ""
            expectedSubst
            (orderRenameAndRenormalizeTODO (ElemVar Mock.x) originalSubst)
    ]
  where
    targetVarX = ElemVar . mkElementTarget $ Mock.x
    targetPattX = mkElemVar . mkElementTarget $ Mock.x
    nonTargetVarY = ElemVar . mkElementNonTarget $ Mock.y
    nonTargetPattY = mkElemVar . mkElementNonTarget $ Mock.y
    nonTargetVarZ = ElemVar . mkElementNonTarget $ Mock.z
    nonTargetPattZ = mkElemVar . mkElementNonTarget $ Mock.z

emptyRawSubst :: [(UnifiedVariable Variable, TermLike Variable)]
emptyRawSubst = mempty

emptySubst :: Substitution Variable
emptySubst = mempty

singletonSubst :: [(UnifiedVariable Variable, TermLike Variable)]
singletonSubst = [(ElemVar Mock.x, Mock.a)]

test_toPredicate :: TestTree
test_toPredicate =
    testCase "toPredicate" $ do
        assertEqual "null substitutions is top"
            makeTruePredicate_
            (toPredicate mempty :: Predicate Variable)
        assertEqual "a = b"
            (makeAndPredicate pr1 makeTruePredicate_)
            (toPredicate $ wrap
                [(ElemVar $ a Mock.testSort, mkElemVar $ b Mock.testSort)]
            )

pr1 :: Predicate Variable
pr1 =
    makeEqualsPredicate_
        (mkElemVar $ a Mock.testSort)
        (mkElemVar $ b Mock.testSort)

a, b :: Sort -> ElementVariable Variable
a = ElementVariable . Variable (testId "a") mempty
b = ElementVariable . Variable (testId "b") mempty
