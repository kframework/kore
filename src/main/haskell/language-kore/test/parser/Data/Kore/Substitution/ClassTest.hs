{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances  #-}
module Data.Kore.Substitution.ClassTest where

import           Test.Tasty                           (TestTree, testGroup)
import           Test.Tasty.HUnit                     (assertEqual, testCase)

import           Data.Kore.AST
import           Data.Kore.Substitution.Class
import qualified Data.Kore.Substitution.List          as S
import           Data.Kore.Variables.Fresh.IntCounter
import           Data.Kore.Variables.Int

import           Data.Kore.Substitution.TestCommon

type UnifiedPatternSubstitution =
    S.Substitution (UnifiedVariable Variable) UnifiedPattern

instance PatternSubstitutionClass Variable UnifiedPatternSubstitution IntCounter
  where

testSubstitute
    :: UnifiedPattern
    -> UnifiedPatternSubstitution
    -> IntCounter UnifiedPattern
testSubstitute = substitute

substitutionClassTests :: TestTree
substitutionClassTests =
    testGroup
        "Substitution.List Tests"
        [ testCase "Testing substituting a variable."
            (assertEqual ""
                (objectTopPattern, 2)
                (runIntCounter
                    (testSubstitute objectVariableUnifiedPattern substitution1)
                    2
                )
            )
        , testCase "Testing not substituting a variable."
            (assertEqual ""
                (metaVariableUnifiedPattern, 2)
                (runIntCounter
                    (testSubstitute metaVariableUnifiedPattern substitution1)
                    2
                )
            )
        , testCase "Testing not substituting anything."
            (assertEqual ""
                (objectBottomPattern, 2)
                (runIntCounter
                    (testSubstitute objectBottomPattern substitution1)
                    2
                )
            )
         , testCase "Testing exists => empty substitution."
            (assertEqual ""
                (existsObjectUnifiedPattern1, 2)
                (runIntCounter
                    (testSubstitute existsObjectUnifiedPattern1 substitution1)
                    2
                )
            )
         , testCase "Testing forall."
            (assertEqual ""
                (forallObjectUnifiedPattern2, 2)
                (runIntCounter
                    (testSubstitute forallObjectUnifiedPattern1 substitution1)
                    2
                )
            )
         , testCase "Testing binder renaming"
            (assertEqual ""
                (existsObjectUnifiedPattern1S 2, 3)
                (runIntCounter
                    (testSubstitute existsObjectUnifiedPattern1 substitution2)
                    2
                )
            )
          , testCase "Testing binder renaming and substitution"
            (assertEqual ""
                (forallObjectUnifiedPattern1S3, 6)
                (runIntCounter
                    (testSubstitute forallObjectUnifiedPattern1 substitution3)
                    5
                )
            )
          , testCase "Testing double binder renaming"
            (assertEqual ""
                (forallExistsObjectUnifiedPattern1S2, 9)
                (runIntCounter
                    (testSubstitute
                        forallExistsObjectUnifiedPattern1 substitution2)
                    7
                )
            )
           , testCase "Testing double binder renaming 1"
            (assertEqual ""
                (forallExistsObjectUnifiedPattern2, 17)
                (runIntCounter
                    (testSubstitute
                        forallExistsObjectUnifiedPattern2 substitution1)
                    17
                )
            )
           , testCase "Testing substitution state 1"
            (assertEqual ""
                (testSubstitutionStatePatternS3, 18)
                (runIntCounter
                    (testSubstitute
                        testSubstitutionStatePattern substitution3)
                    17
                )
            )
           ]

metaVariableSubstitute :: Int -> Variable Meta
metaVariableSubstitute = intVariable metaVariable

metaVariableUnifiedPatternSubstitute :: Int -> UnifiedPattern
metaVariableUnifiedPatternSubstitute =
    MetaPattern . VariablePattern . metaVariableSubstitute

objectVariableSubstitute :: Int -> Variable Object
objectVariableSubstitute = intVariable objectVariable

objectVariableUnifiedPatternSubstitute :: Int -> UnifiedPattern
objectVariableUnifiedPatternSubstitute =
    ObjectPattern . VariablePattern . objectVariableSubstitute

substitution1 :: UnifiedPatternSubstitution
substitution1 = S.fromList
  [ (unifiedObjectVariable, objectTopPattern) ]

substitution2 :: UnifiedPatternSubstitution
substitution2 = S.fromList
  [ (unifiedMetaVariable, objectVariableUnifiedPattern) ]

substitution3 :: UnifiedPatternSubstitution
substitution3 = S.fromList
  [ (unifiedObjectVariable, metaVariableUnifiedPattern) ]

existsObjectUnifiedPattern1 :: UnifiedPattern
existsObjectUnifiedPattern1 = ObjectPattern $ ExistsPattern Exists
    { existsSort = objectSort
    , existsVariable = objectVariable
    , existsChild = objectVariableUnifiedPattern
    }

existsMetaUnifiedPattern1 :: UnifiedPattern
existsMetaUnifiedPattern1 = MetaPattern $ ExistsPattern Exists
    { existsSort = metaSort
    , existsVariable = metaVariable
    , existsChild = metaVariableUnifiedPattern
    }

existsMetaUnifiedPattern1S3 :: UnifiedPattern
existsMetaUnifiedPattern1S3 = MetaPattern $ ExistsPattern Exists
    { existsSort = metaSort
    , existsVariable = metaVariableSubstitute 17
    , existsChild = metaVariableUnifiedPatternSubstitute 17
    }

existsObjectUnifiedPattern1S :: Int -> UnifiedPattern
existsObjectUnifiedPattern1S n = ObjectPattern $ ExistsPattern Exists
    { existsSort = objectSort
    , existsVariable = objectVariableSubstitute n
    , existsChild = objectVariableUnifiedPatternSubstitute n
    }

forallObjectUnifiedPattern1 :: UnifiedPattern
forallObjectUnifiedPattern1 = MetaPattern $ ForallPattern Forall
    { forallSort = metaSort
    , forallVariable = metaVariable
    , forallChild = objectVariableUnifiedPattern
    }

forallObjectUnifiedPattern2 :: UnifiedPattern
forallObjectUnifiedPattern2 = MetaPattern $ ForallPattern Forall
    { forallSort = metaSort
    , forallVariable = metaVariable
    , forallChild = objectTopPattern
    }

forallObjectUnifiedPattern1S3 :: UnifiedPattern
forallObjectUnifiedPattern1S3 = MetaPattern $ ForallPattern Forall
    { forallSort = metaSort
    , forallVariable = metaVariableSubstitute 5
    , forallChild = metaVariableUnifiedPattern
    }

forallExistsObjectUnifiedPattern1 :: UnifiedPattern
forallExistsObjectUnifiedPattern1 = ObjectPattern $ ForallPattern Forall
    { forallSort = objectSort
    , forallVariable = objectVariable
    , forallChild = existsObjectUnifiedPattern1
    }

forallExistsObjectUnifiedPattern2 :: UnifiedPattern
forallExistsObjectUnifiedPattern2 = MetaPattern $ ForallPattern Forall
    { forallSort = metaSort
    , forallVariable = metaVariable
    , forallChild = existsObjectUnifiedPattern1
    }

forallExistsObjectUnifiedPattern1S2 :: UnifiedPattern
forallExistsObjectUnifiedPattern1S2 = ObjectPattern $ ForallPattern Forall
    { forallSort = objectSort
    , forallVariable = objectVariableSubstitute 7
    , forallChild = existsObjectUnifiedPattern1S 8
    }

testSubstitutionStatePattern :: UnifiedPattern
testSubstitutionStatePattern = ObjectPattern $ ApplicationPattern Application
    { applicationSymbolOrAlias = SymbolOrAlias
        { symbolOrAliasConstructor = Id "sigma"
        , symbolOrAliasParams = []
        }
    , applicationChildren =
        [ existsObjectUnifiedPattern1
        , objectVariableUnifiedPattern
        , existsMetaUnifiedPattern1
        , metaVariableUnifiedPattern
        ]
    }

testSubstitutionStatePatternS3 :: UnifiedPattern
testSubstitutionStatePatternS3 = ObjectPattern $ ApplicationPattern Application
    { applicationSymbolOrAlias = SymbolOrAlias
        { symbolOrAliasConstructor = Id "sigma"
        , symbolOrAliasParams = []
        }
    , applicationChildren =
        [ existsObjectUnifiedPattern1
        , metaVariableUnifiedPattern
        , existsMetaUnifiedPattern1S3
        , metaVariableUnifiedPattern
        ]
    }
