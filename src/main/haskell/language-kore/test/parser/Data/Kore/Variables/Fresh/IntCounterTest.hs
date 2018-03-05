module Data.Kore.Variables.Fresh.IntCounterTest where

import           Test.Tasty                           (TestTree, testGroup)
import           Test.Tasty.HUnit                     (assertEqual,
                                                       assertFailure, testCase)

import           Control.Exception                    (ErrorCall (ErrorCall),
                                                       catch, evaluate)

import           Data.Kore.AST
import           Data.Kore.Variables.Fresh.Class
import           Data.Kore.Variables.Fresh.IntCounter

objectVariable :: Variable Object
objectVariable = Variable
    { variableName = Id "v"
    , variableSort = SortVariableSort (SortVariable (Id "s"))
    }

metaVariable :: Variable Meta
metaVariable = Variable
    { variableName = Id "#v"
    , variableSort = SortVariableSort (SortVariable (Id "#s"))
    }

unifiedMetaVariable :: UnifiedVariable Variable
unifiedMetaVariable = MetaVariable metaVariable

variablesFreshIntCounterTests :: TestTree
variablesFreshIntCounterTests =
    testGroup
        "Variables.Fresh.IntCounter Tests"
        [ testCase "Testing freshVariable Object 2."
            (assertEqual ""
                (objectVariable { variableName = Id "var_2" }, 3)
                (runIntCounter (freshVariable objectVariable) 2)
            )
        , testCase "Testing freshVariable Meta 2."
            (assertEqual ""
                (metaVariable { variableName = Id "#var_2" }, 3)
                (runIntCounter (freshVariable metaVariable) 2)
            )
        , testCase "Testing freshVariable Functor Meta 1."
            (assertEqual ""
                (( metaVariable { variableName = Id "#var_1" }
                 , metaVariable { variableName = Id "#var_2" }), 3)
                (runIntCounter
                    ((,)
                        <$> freshVariable metaVariable
                        <*> freshVariable metaVariable
                    ) 1)
             )
        , testCase "Testing freshUnifiedVariable Meta 2."
            (assertEqual ""
                (metaVariable { variableName = Id "#var_2" }, 3)
                (runIntCounter
                    (freshVariable metaVariable) 2)
            )
        , testCase "Testing failing freshVariableSuchThat Meta 1."
            ((evaluate (runIntCounter
                    (freshVariableSuchThat
                        metaVariable
                        (== metaVariable)
                    ) 2) >> assertFailure "This evaluation should fail")
                `catch` \ (ErrorCall s) ->
                        assertEqual ""
                            "Cannot generate variable satisfying predicate"
                            s
            )
        , testCase "Testing freshVariableSuchThat Meta 1."
            (assertEqual ""
                (metaVariable { variableName = Id "#var_2" }, 3)
                (runIntCounter
                    (freshVariableSuchThat
                        metaVariable
                        (const True)
                    ) 2)
            )
        ]
