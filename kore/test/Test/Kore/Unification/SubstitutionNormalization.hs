module Test.Kore.Unification.SubstitutionNormalization
    (test_substitutionNormalization) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Control.Monad.Except as Except
import qualified Data.Default as Default
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import           Kore.Attribute.Symbol
import           Kore.IndexedModule.MetadataTools
                 ( MetadataTools (..), SmtMetadataTools )
import qualified Kore.IndexedModule.MetadataTools as HeadType
                 ( HeadType (..) )
import qualified Kore.Internal.Pattern as Conditional
import           Kore.Internal.TermLike
import           Kore.Syntax.PatternF
                 ( groundHead )
import           Kore.Unification.Error
                 ( SubstitutionError (..) )
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unification.SubstitutionNormalization

import           Test.Kore
import           Test.Kore.Comparators ()
import qualified Test.Kore.IndexedModule.MockMetadataTools as Mock
import qualified Test.Kore.Step.MockSymbols as Mock
import           Test.Tasty.HUnit.Extensions

test_substitutionNormalization :: [TestTree]
test_substitutionNormalization =
    [ testCase "Empty substitution"
        (assertEqualWithExplanation ""
            (Right [])
            (runNormalizeSubstitution
                ([] :: [(Variable, TermLike Variable)])
            )
        )
    , testCase "Simple substitution"
        (assertEqualWithExplanation ""
            (Right [(v1 Mock.testSort, mkTop_)])
            (runNormalizeSubstitution
                [(v1 Mock.testSort, mkTop_)]
            )
        )
    , testCase "Simple unnormalized substitution"
        (assertEqualWithExplanation ""
            (Right
                [ (v1 Mock.testSort, mkTop Mock.testSort)
                , (x1 Mock.testSort, mkTop Mock.testSort)
                ]
            )
            (runNormalizeSubstitution
                [ (v1 Mock.testSort, mkVar $ x1 Mock.testSort)
                , (x1 Mock.testSort, mkTop Mock.testSort)
                ]
            )
        )
    , testCase "Unnormalized substitution with 'and'"
        (assertEqualWithExplanation ""
            (Right
                [   ( v1 Mock.testSort
                    , mkAnd mkTop_ (mkTop Mock.testSort)
                    )
                , (x1 Mock.testSort, mkTop Mock.testSort)
                ]
            )
            (runNormalizeSubstitution
                [   ( v1 Mock.testSort
                    , mkAnd (mkVar $ x1 Mock.testSort) mkTop_
                    )
                ,   (x1 Mock.testSort, mkTop Mock.testSort)
                ]
            )
        )
    , let
        var1 =  (v1 Mock.testSort)
      in
        testCase "Simplest cycle"
            (assertEqualWithExplanation ""
                (Right [])
                (runNormalizeSubstitution [(var1, mkVar $ v1 Mock.testSort)])
            )
    , let
        var1 =  (v1 Mock.testSort)
        varx1 =  (x1 Mock.testSort)
      in
        testCase "Cycle with extra substitution"
            (assertEqualWithExplanation ""
                (Right [(x1 Mock.testSort, mkVar $ v1 Mock.testSort)])
                (runNormalizeSubstitution
                    [ (var1, mkVar $ v1 Mock.testSort)
                    , (varx1, mkVar $ v1 Mock.testSort)
                    ]
                )
            )
    , let
        var1 =  (v1 Mock.testSort)
      in
        testCase "Function cycle"
            (assertEqualWithExplanation ""
                (Left (NonCtorCircularVariableDependency [var1]))
                (runNormalizeSubstitution
                    [   ( var1
                        , mkApp Mock.testSort f [mkVar var1]
                        )
                    ]
                )
            )
    , let
        var1 =  (v1 Mock.testSort)
        varx1 =  (x1 Mock.testSort)
      in
        testCase "Length 2 cycle"
            (assertEqualWithExplanation ""
                (Right [])
                (runNormalizeSubstitution
                    [ (var1, mkVar $ x1 Mock.testSort)
                    , (varx1, mkVar $ v1 Mock.testSort)
                    ]
                )
            )
    , let
        var1 =  (v1 Mock.testSort)
        varx1 =  (x1 Mock.testSort)
      in
        testCase "Cycle with 'and'"
            (assertEqualWithExplanation ""
                (Right [])
                (runNormalizeSubstitution
                    [ (var1, mkAnd (mkVar $ x1 Mock.testSort) mkTop_)
                    , (varx1, mkAnd (mkVar $ v1 Mock.testSort) mkTop_)
                    ]
                )
            )
    , let
        var1 =  (v1 Mock.testSort)
        varx1 =  (x1 Mock.testSort)
      in
        testCase "Length 2 non-ctor cycle"
            (assertEqualWithExplanation ""
                (Left (NonCtorCircularVariableDependency [var1, varx1]))
                (runNormalizeSubstitution
                    [ (var1, mkApp Mock.testSort f [mkVar varx1])
                    , (varx1, mkVar var1)
                    ]
                )
            )
    , testCase "Constructor cycle"
        (assertEqualWithExplanation ""
            (Right [])
            (runNormalizeSubstitutionObject
                [ (Mock.x, Mock.constr10 (mkVar Mock.x))
                ]
            )
        )
    , testCase "Constructor with side function cycle"
        (assertEqualWithExplanation ""
            (Right [])
            (runNormalizeSubstitutionObject
                [ (Mock.x, Mock.constr20 (Mock.f (mkVar Mock.x)) (mkVar Mock.x))
                ]
            )
        )
    , testCase "Constructor with function cycle"
        (assertEqualWithExplanation ""
            (Left (NonCtorCircularVariableDependency [Mock.x]))
            (runNormalizeSubstitutionObject
                [ (Mock.x, Mock.constr10 (Mock.f (mkVar Mock.x)))
                ]
            )
        )
    ]
  where
    v1 :: Sort -> Variable
    v1 = Variable (testId "v1") mempty
    x1 :: Sort -> Variable
    x1 = Variable (testId "x1") mempty
    f = groundHead "f" AstLocationTest

runNormalizeSubstitution
    :: [(Variable, TermLike Variable)]
    -> Either SubstitutionError [(Variable, TermLike Variable)]
runNormalizeSubstitution substitution =
    fmap (Substitution.unwrap . Conditional.substitution)
    . Except.runExcept
    $ normalizeSubstitution mockMetadataTools (Map.fromList substitution)

runNormalizeSubstitutionObject
    :: [(Variable, TermLike Variable)]
    -> Either SubstitutionError [(Variable, TermLike Variable)]
runNormalizeSubstitutionObject substitution =
    fmap (Substitution.unwrap . Conditional.substitution)
    . Except.runExcept
    $ normalizeSubstitution Mock.metadataTools (Map.fromList substitution)

mockMetadataTools :: SmtMetadataTools StepperAttributes
mockMetadataTools = MetadataTools
    { symAttributes = const Mock.functionalAttributes
    , symbolOrAliasType = const HeadType.Symbol
    , sortAttributes = const Default.def
    , isSubsortOf = const $ const False
    , subsorts = Set.singleton
    , applicationSorts = undefined
    , smtData = undefined
    }
