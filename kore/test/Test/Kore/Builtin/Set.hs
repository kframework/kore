module Test.Kore.Builtin.Set where

import           GHC.Stack
                 ( HasCallStack )
import           Hedgehog hiding
                 ( Concrete, property )
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import           Test.Tasty
import           Test.Tasty.HUnit

import qualified Control.Monad as Monad
import qualified Control.Monad.Trans as Trans
import qualified Data.Default as Default
import qualified Data.Foldable as Foldable
import qualified Data.List as List
import qualified Data.Reflection as Reflection
import qualified Data.Sequence as Seq
import           Data.Set
                 ( Set )
import qualified Data.Set as Set

import           Kore.Attribute.Hook
                 ( Hook )
import qualified Kore.Attribute.Symbol as StepperAttributes
import qualified Kore.Builtin.Set as Set
import           Kore.IndexedModule.MetadataTools
                 ( SmtMetadataTools )
import           Kore.Internal.MultiOr
                 ( MultiOr (..) )
import           Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
                 ( TermLike, fromConcrete, mkAnd, mkApplySymbol, mkEquals_,
                 mkVar )
import           Kore.Predicate.Predicate as Predicate
import           Kore.Sort
                 ( Sort )
import           Kore.Step.Rule
                 ( RewriteRule (RewriteRule), RulePattern (RulePattern) )
import           Kore.Step.Rule as RulePattern
                 ( RulePattern (..) )
import           Kore.Syntax.Id
                 ( Id )
import           Kore.Syntax.Variable
                 ( Concrete, Variable (Variable, variableName) )
import qualified Kore.Syntax.Variable as DoNotUse
                 ( Variable (..) )
import qualified Kore.Unification.Substitution as Substitution
import qualified SMT


import           Test.Kore
                 ( standaloneGen, testId, variableGen )
import qualified Test.Kore.Builtin.Bool as Test.Bool
import           Test.Kore.Builtin.Builtin
import           Test.Kore.Builtin.Definition
import           Test.Kore.Builtin.Int
                 ( genConcreteIntegerPattern, genInteger, genIntegerPattern )
import qualified Test.Kore.Builtin.Int as Test.Int
import qualified Test.Kore.Builtin.List as Test.List
import           Test.Kore.Comparators ()
import qualified Test.Kore.Step.MockSymbols as Mock
import           Test.SMT
import           Test.Tasty.HUnit.Extensions

genSetInteger :: Gen (Set Integer)
genSetInteger = Gen.set (Range.linear 0 32) genInteger

genSetConcreteIntegerPattern :: Gen (Set (TermLike Concrete))
genSetConcreteIntegerPattern =
    Set.map Test.Int.asInternal <$> genSetInteger

genConcreteSet :: Gen (Set (TermLike Concrete))
genConcreteSet = genSetConcreteIntegerPattern

genSetPattern :: Gen (TermLike Variable)
genSetPattern = asTermLike <$> genSetConcreteIntegerPattern

test_getUnit :: TestTree
test_getUnit =
    testPropertyWithSolver
        "in{}(_, unit{}() === \\dv{Bool{}}(\"false\")"
        (do
            patKey <- forAll genIntegerPattern
            let patIn =
                    mkApplySymbol
                        inSetSymbol
                        [ patKey
                        , mkApplySymbol unitSetSymbol []
                        ]
                patFalse = Test.Bool.asInternal False
                predicate = mkEquals_ patFalse patIn
            (===) (Test.Bool.asPattern False) =<< evaluateT patIn
            (===) Pattern.top                 =<< evaluateT predicate
        )

test_inElement :: TestTree
test_inElement =
    testPropertyWithSolver
        "in{}(x, element{}(x)) === \\dv{Bool{}}(\"true\")"
        (do
            patKey <- forAll genIntegerPattern
            let patIn = mkApplySymbol inSetSymbol [ patKey, patElement ]
                patElement = mkApplySymbol elementSetSymbol [ patKey ]
                patTrue = Test.Bool.asInternal True
                predicate = mkEquals_ patIn patTrue
            (===) (Test.Bool.asPattern True) =<< evaluateT patIn
            (===) Pattern.top                =<< evaluateT predicate
        )

test_inConcat :: TestTree
test_inConcat =
    testPropertyWithSolver
        "in{}(concat{}(_, element{}(e)), e) === \\dv{Bool{}}(\"true\")"
        (do
            elem' <- forAll genConcreteIntegerPattern
            values <- forAll genSetConcreteIntegerPattern
            let patIn = mkApplySymbol inSetSymbol [ patElem , patSet ]
                patSet = asTermLike $ Set.insert elem' values
                patElem = fromConcrete elem'
                patTrue = Test.Bool.asInternal True
                predicate = mkEquals_ patTrue patIn
            (===) (Test.Bool.asPattern True) =<< evaluateT patIn
            (===) Pattern.top                =<< evaluateT predicate
        )

test_concatUnit :: TestTree
test_concatUnit =
    testPropertyWithSolver
        "concat{}(unit{}(), xs) === concat{}(xs, unit{}()) === xs"
        (do
            patValues <- forAll genSetPattern
            let patUnit = mkApplySymbol unitSetSymbol []
                patConcat1 =
                    mkApplySymbol concatSetSymbol [ patUnit, patValues ]
                patConcat2 =
                    mkApplySymbol concatSetSymbol [ patValues, patUnit ]
                predicate1 = mkEquals_ patValues patConcat1
                predicate2 = mkEquals_ patValues patConcat2
            expect <- evaluateT patValues
            (===) expect      =<< evaluateT patConcat1
            (===) expect      =<< evaluateT patConcat2
            (===) Pattern.top =<< evaluateT predicate1
            (===) Pattern.top =<< evaluateT predicate2
        )

test_concatAssociates :: TestTree
test_concatAssociates =
    testPropertyWithSolver
        "concat{}(concat{}(as, bs), cs) === concat{}(as, concat{}(bs, cs))"
        (do
            patSet1 <- forAll genSetPattern
            patSet2 <- forAll genSetPattern
            patSet3 <- forAll genSetPattern
            let patConcat12 = mkApplySymbol concatSetSymbol [ patSet1, patSet2 ]
                patConcat23 = mkApplySymbol concatSetSymbol [ patSet2, patSet3 ]
                patConcat12_3 =
                    mkApplySymbol concatSetSymbol [ patConcat12, patSet3 ]
                patConcat1_23 =
                    mkApplySymbol concatSetSymbol [ patSet1, patConcat23 ]
                predicate = mkEquals_ patConcat12_3 patConcat1_23
            concat12_3 <- evaluateT patConcat12_3
            concat1_23 <- evaluateT patConcat1_23
            (===) concat12_3 concat1_23
            (===) Pattern.top =<< evaluateT predicate
        )

test_difference :: TestTree
test_difference =
    testPropertyWithSolver
        "SET.difference is difference"
        (do
            set1 <- forAll genSetConcreteIntegerPattern
            set2 <- forAll genSetConcreteIntegerPattern
            let set3 = Set.difference set1 set2
                patSet3 = asTermLike set3
                patDifference =
                    mkApplySymbol
                        differenceSetSymbol
                        [ asTermLike set1, asTermLike set2 ]
                predicate = mkEquals_ patSet3 patDifference
            expect <- evaluateT patSet3
            (===) expect      =<< evaluateT patDifference
            (===) Pattern.top =<< evaluateT predicate
        )

test_toList :: TestTree
test_toList =
    testPropertyWithSolver
        "SET.set2list is set2list"
        (do
            set1 <- forAll genSetConcreteIntegerPattern
            let set2 = fmap fromConcrete . Seq.fromList . Set.toList $ set1
                patSet2 = Test.List.asTermLike set2
                patToList =
                    mkApplySymbol
                        toListSetSymbol
                        [ asTermLike set1 ]
                predicate = mkEquals_ patSet2 patToList
            expect <- evaluateT patSet2
            (===) expect      =<< evaluateT patToList
            (===) Pattern.top =<< evaluateT predicate
        )

test_size :: TestTree
test_size =
    testPropertyWithSolver
        "SET.size is size"
        (do
            set <- forAll genSetConcreteIntegerPattern
            let
                size = Set.size set
                patExpected = Test.Int.asInternal $ toInteger size
                patActual =
                    mkApplySymbol
                        sizeSetSymbol
                        [ asTermLike set ]
                predicate = mkEquals_ patExpected patActual
            expect <- evaluateT patExpected
            (===) expect      =<< evaluateT patActual
            (===) Pattern.top =<< evaluateT predicate
        )

test_intersection_unit :: TestTree
test_intersection_unit =
    testPropertyWithSolver "intersection(as, unit()) === unit()" $ do
        as <- forAll genSetPattern
        let
            original = intersectionSet as unitSet
            expect = Pattern.fromTermLike (asInternal Set.empty)
        (===) expect      =<< evaluateT original
        (===) Pattern.top =<< evaluateT (mkEquals_ original unitSet)

test_intersection_idem :: TestTree
test_intersection_idem =
    testPropertyWithSolver "intersection(as, as) === as" $ do
        as <- forAll genConcreteSet
        let
            termLike = asTermLike as
            original = intersectionSet termLike termLike
            expect = Pattern.fromTermLike (asInternal as)
        (===) expect      =<< evaluateT original
        (===) Pattern.top =<< evaluateT (mkEquals_ original termLike)

setVariableGen :: Sort -> Gen (Set Variable)
setVariableGen sort =
    Gen.set (Range.linear 0 32) (standaloneGen $ variableGen sort)

-- | Sets with symbolic keys are not simplified.
test_symbolic :: TestTree
test_symbolic =
    testPropertyWithSolver
        "builtin functions are not evaluated on symbolic keys"
        (do
            values <- forAll (setVariableGen intSort)
            let patMap = asSymbolicPattern (Set.map mkVar values)
                expect = Pattern.fromTermLike patMap
            if Set.null values
                then discard
                else (===) expect =<< evaluateT patMap
        )

-- | Construct a pattern for a map which may have symbolic keys.
asSymbolicPattern
    :: Set (TermLike Variable)
    -> TermLike Variable
asSymbolicPattern result
    | Set.null result =
        applyUnit
    | otherwise =
        foldr1 applyConcat (applyElement <$> Set.toAscList result)
  where
    applyUnit = mkApplySymbol unitSetSymbol []
    applyElement key = mkApplySymbol elementSetSymbol [key]
    applyConcat set1 set2 = mkApplySymbol concatSetSymbol [set1, set2]

{- | Check that unifying a concrete set with itself results in the same set
 -}
test_unifyConcreteIdem :: TestTree
test_unifyConcreteIdem =
    testPropertyWithSolver
        "unify concrete set with itself"
        (do
            patSet <- forAll genSetPattern
            let patAnd = mkAnd patSet patSet
                predicate = mkEquals_ patSet patAnd
            expect <- evaluateT patSet
            (===) expect      =<< evaluateT patAnd
            (===) Pattern.top =<< evaluateT predicate
        )

test_unifyConcreteDistinct :: TestTree
test_unifyConcreteDistinct =
    testPropertyWithSolver
        "(dis)unify two distinct sets"
        (do
            set1 <- forAll genSetConcreteIntegerPattern
            patElem <- forAll genConcreteIntegerPattern
            Monad.when (Set.member patElem set1) discard
            let set2 = Set.insert patElem set1
                patSet1 = asTermLike set1
                patSet2 = asTermLike set2
                conjunction = mkAnd patSet1 patSet2
                predicate = mkEquals_ patSet1 conjunction
            (===) Pattern.bottom =<< evaluateT conjunction
            (===) Pattern.bottom =<< evaluateT predicate
        )

test_unifyFramingVariable :: TestTree
test_unifyFramingVariable =
    testPropertyWithSolver
        "unify a concrete set and a framed set"
        (do
            framedElem <- forAll genConcreteIntegerPattern
            concreteSet <-
                (<$>)
                    (Set.insert framedElem)
                    (forAll genSetConcreteIntegerPattern)
            frameVar <- forAll (standaloneGen $ variableGen setSort)
            let framedSet = Set.singleton framedElem
                patConcreteSet = asTermLike concreteSet
                patFramedSet =
                    mkApplySymbol concatSetSymbol
                        [ asTermLike framedSet
                        , mkVar frameVar
                        ]
                remainder = Set.delete framedElem concreteSet
            let
                expect = do  -- list monad
                    set <- [remainder, concreteSet]
                    return Conditional
                        { term = asInternal concreteSet
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [(frameVar, asInternal set)]
                        }
            actual <- Trans.lift $ evaluateToList (mkAnd patConcreteSet patFramedSet)
            (===) (List.sort expect) actual
        )

-- Given a function to scramble the arguments to concat, i.e.,
-- @id@ or @reverse@, produces a pattern of the form
-- `SetItem(absInt(X:Int)) Rest:Set`, or
-- `Rest:Set SetItem(absInt(X:Int))`, respectively.
selectFunctionPattern
    :: Variable          -- ^element variable
    -> Variable          -- ^set variable
    -> (forall a . [a] -> [a])  -- ^scrambling function
    -> TermLike Variable
selectFunctionPattern elementVar setVar permutation  =
    mkApplySymbol concatSetSymbol $ permutation [singleton, mkVar setVar]
  where
    element = mkApplySymbol absIntSymbol  [mkVar elementVar]
    singleton = mkApplySymbol elementSetSymbol [ element ]

makeElementVariable :: Variable -> TermLike Variable
makeElementVariable var =
    mkApplySymbol elementSetSymbol [mkVar var]

-- Given a function to scramble the arguments to concat, i.e.,
-- @id@ or @reverse@, produces a pattern of the form
-- `SetItem(X:Int) Rest:Set`, or `Rest:Set SetItem(X:Int)`, respectively.
selectPattern
    :: Variable          -- ^element variable
    -> Variable          -- ^set variable
    -> (forall a . [a] -> [a])  -- ^scrambling function
    -> TermLike Variable
selectPattern elementVar setVar permutation  =
    mkApplySymbol concatSetSymbol
    $ permutation [makeElementVariable elementVar, mkVar setVar]

addSelectElement
    :: Variable           -- ^element variable
    -> TermLike Variable  -- ^existingPattern
    -> TermLike Variable
addSelectElement elementVar setPattern  =
    mkApplySymbol concatSetSymbol [makeElementVariable elementVar, setPattern]

test_unifySelectFromEmpty :: TestTree
test_unifySelectFromEmpty =
    testPropertyWithSolver "unify an empty set with a selection pattern" $ do
        elementVar <- forAll (standaloneGen $ variableGen intSort)
        setVar <- forAll (standaloneGen $ variableGen setSort)
        Monad.when (variableName elementVar == variableName setVar) discard
        let selectPat       = selectPattern elementVar setVar id
            selectPatRev    = selectPattern elementVar setVar reverse
            fnSelectPat     = selectFunctionPattern elementVar setVar id
            fnSelectPatRev  = selectFunctionPattern elementVar setVar reverse
        -- Set.empty /\ SetItem(X:Int) Rest:Set
        emptySet `doesNotUnifyWith` selectPat
        selectPat `doesNotUnifyWith` emptySet
        -- Set.empty /\ Rest:Set SetItem(X:Int)
        emptySet `doesNotUnifyWith` selectPatRev
        selectPatRev `doesNotUnifyWith` emptySet
        -- Set.empty /\ SetItem(absInt(X:Int)) Rest:Set
        emptySet `doesNotUnifyWith` fnSelectPat
        fnSelectPat `doesNotUnifyWith` emptySet
        -- Set.empty /\ Rest:Set SetItem(absInt(X:Int))
        emptySet `doesNotUnifyWith` fnSelectPatRev
        fnSelectPatRev `doesNotUnifyWith` emptySet
  where
    emptySet = asTermLike Set.empty
    doesNotUnifyWith pat1 pat2 = do
        annotateShow pat1
        annotateShow pat2
        (===) Pattern.bottom =<< evaluateT(mkAnd pat1 pat2)

test_unifySelectFromSingleton :: TestTree
test_unifySelectFromSingleton =
    testPropertyWithSolver
        "unify a singleton set with a variable selection pattern"
        (do
            concreteElem <- forAll genConcreteIntegerPattern
            elementVar <- forAll (standaloneGen $ variableGen intSort)
            setVar <- forAll (standaloneGen $ variableGen setSort)
            Monad.when (variableName elementVar == variableName setVar) discard
            let selectPat       = selectPattern elementVar setVar id
                selectPatRev    = selectPattern elementVar setVar reverse
                singleton       = asInternal (Set.singleton concreteElem)
                elemStepPattern = fromConcrete concreteElem
                expect1 =
                    Conditional
                        { term = singleton
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [ (setVar, asInternal Set.empty)
                                , (elementVar, elemStepPattern)
                                ]
                        }
                expect2 =
                    Conditional
                        { term = singleton
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [ (setVar, singleton)
                                , (elementVar, elemStepPattern)
                                ]
                        }
            -- { 5 } /\ SetItem(X:Int) Rest:Set
            (singleton `unifiesWithMulti` selectPat) [expect1, expect2]
            (selectPat `unifiesWithMulti` singleton) [expect1, expect2]
            -- { 5 } /\ Rest:Set SetItem(X:Int)
            (singleton `unifiesWithMulti` selectPatRev) [expect1, expect2]
            (selectPatRev `unifiesWithMulti` singleton) [expect1, expect2]
        )

test_unifySelectFromSingletonWithoutLeftovers :: TestTree
test_unifySelectFromSingletonWithoutLeftovers =
    testPropertyWithSolver
        "unify a singleton set with an element variable"
        (do
            concreteElem <- forAll genConcreteIntegerPattern
            elementVar <- forAll (standaloneGen $ variableGen intSort)
            let selectPat       = makeElementVariable elementVar
                singleton       = asInternal (Set.singleton concreteElem)
                elemStepPattern = fromConcrete concreteElem
                expect =
                    Conditional
                        { term = singleton
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [ (elementVar, elemStepPattern) ]
                        }
            -- { 5 } /\ SetItem(X:Int)
            (singleton `unifiesWith` selectPat) expect
            (selectPat `unifiesWith` singleton) expect
        )

test_unifySelectFromTwoElementSet :: TestTree
test_unifySelectFromTwoElementSet =
    testPropertyWithSolver
        "unify a two element set with a variable selection pattern"
        (do
            concreteElem1 <- forAll genConcreteIntegerPattern
            concreteElem2 <- forAll genConcreteIntegerPattern
            Monad.when (concreteElem1 == concreteElem2) discard

            elementVar <- forAll (standaloneGen $ variableGen intSort)
            setVar <- forAll (standaloneGen $ variableGen setSort)
            Monad.when (variableName elementVar == variableName setVar) discard

            let selectPat = selectPattern elementVar setVar id
                selectPatRev = selectPattern elementVar setVar reverse
                set = asInternal (Set.fromList [concreteElem1, concreteElem2])
                elemStepPattern1 = fromConcrete concreteElem1
                elemStepPattern2 = fromConcrete concreteElem2
                expect1 =
                    Conditional
                        { term = set
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [   ( setVar
                                    , asInternal (Set.fromList [concreteElem2])
                                    )
                                , (elementVar, elemStepPattern1)
                                ]
                        }
                expect2 =
                    Conditional
                        { term = set
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [ (setVar, set)
                                , (elementVar, elemStepPattern1)
                                ]
                        }
                expect3 =
                    Conditional
                        { term = set
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [   ( setVar
                                    , asInternal (Set.fromList [concreteElem1])
                                    )
                                , (elementVar, elemStepPattern2)
                                ]
                        }
                expect4 =
                    Conditional
                        { term = set
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [ (setVar, set)
                                , (elementVar, elemStepPattern2)
                                ]
                        }
            -- { 5 } /\ SetItem(X:Int) Rest:Set
            (set `unifiesWithMulti` selectPat)
                [expect1, expect2, expect3, expect4]
            (selectPat `unifiesWithMulti` set)
                [expect1, expect2, expect3, expect4]
            -- { 5 } /\ Rest:Set SetItem(X:Int)
            (set `unifiesWithMulti` selectPatRev)
                [expect1, expect2, expect3, expect4]
            (selectPatRev `unifiesWithMulti` set)
                [expect1, expect2, expect3, expect4]
        )

test_unifySelectTwoFromTwoElementSet :: TestTree
test_unifySelectTwoFromTwoElementSet =
    testPropertyWithSolver
        "unify a two element set with a variable selection pattern"
        (do
            concreteElem1 <- forAll genConcreteIntegerPattern
            concreteElem2 <- forAll genConcreteIntegerPattern
            Monad.when (concreteElem1 == concreteElem2) discard

            elementVar1 <- forAll (standaloneGen $ variableGen intSort)
            elementVar2 <- forAll (standaloneGen $ variableGen intSort)
            setVar <- forAll (standaloneGen $ variableGen setSort)
            let allVars = [elementVar1, elementVar2, setVar]
            Monad.when (allVars /= List.nub allVars) discard

            let
                selectPat =
                    addSelectElement elementVar1
                    $ addSelectElement elementVar2
                    $ mkVar setVar
                set = asInternal (Set.fromList [concreteElem1, concreteElem2])
                elemStepPattern1 = fromConcrete concreteElem1
                elemStepPattern2 = fromConcrete concreteElem2
                expect = do -- list monad
                    (elementUnifier1, elementUnifier2, setUnifier) <-
                        [   ( elemStepPattern1
                            , elemStepPattern1
                            , [concreteElem2]
                            )
                        ,   ( elemStepPattern1
                            , elemStepPattern1
                            , [concreteElem1, concreteElem2]
                            )
                        ,   ( elemStepPattern2
                            , elemStepPattern2
                            , [concreteElem1]
                            )
                        ,   ( elemStepPattern2
                            , elemStepPattern2
                            , [concreteElem1, concreteElem2]
                            )
                        ]
                        ++ do
                            (eu1, eu2) <-
                                [ (elemStepPattern1, elemStepPattern2)
                                , (elemStepPattern2, elemStepPattern1)
                                ]
                            su <-
                                [ []
                                , [concreteElem1]
                                , [concreteElem2]
                                , [concreteElem1, concreteElem2]
                                ]
                            return (eu1, eu2, su)
                    return Conditional
                        { term = set
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [ (setVar, asInternal (Set.fromList setUnifier))
                                , (elementVar1, elementUnifier1)
                                , (elementVar2, elementUnifier2)
                                ]
                        }
            -- { 5, 6 } /\ SetItem(X:Int) SetItem(Y:Int) Rest:Set
            (set `unifiesWithMulti` selectPat) expect
            (selectPat `unifiesWithMulti` set) expect
        )

-- use as (pat1 `unifiesWith` pat2) expect
unifiesWith
    :: HasCallStack
    => TermLike Variable
    -> TermLike Variable
    -> Pattern Variable
    -> PropertyT SMT.SMT ()
unifiesWith pat1 pat2 expected =
    unifiesWithMulti pat1 pat2 [expected]

-- use as (pat1 `unifiesWithMulti` pat2) expect
unifiesWithMulti
    :: HasCallStack
    => TermLike Variable
    -> TermLike Variable
    -> [Pattern Variable]
    -> PropertyT SMT.SMT ()
unifiesWithMulti pat1 pat2 expectedResults = do
    actualResults <- Trans.lift $ evaluateToList (mkAnd pat1 pat2)
    compareElements (List.sort expectedResults) actualResults
  where
    compareElements [] actuals = [] === actuals
    compareElements expecteds [] =  expecteds === []
    compareElements (expected : expecteds) (actual : actuals) = do
        compareElement expected actual
        compareElements expecteds actuals
    compareElement
        Conditional
            { term = expectedTerm
            , predicate = expectedPredicate
            , substitution = expectedSubstitution
            }
        Conditional
            { term = actualTerm
            , predicate = actualPredicate
            , substitution = actualSubstitution
            }
      = do
        Substitution.toMap expectedSubstitution
            === Substitution.toMap actualSubstitution
        expectedPredicate === actualPredicate
        expectedTerm === actualTerm

test_unifyFnSelectFromSingleton :: TestTree
test_unifyFnSelectFromSingleton =
    testPropertyWithSolver
        "unify a singleton set with a function selection pattern"
        (do
            concreteElem <- forAll genConcreteIntegerPattern
            elementVar <- forAll (standaloneGen $ variableGen intSort)
            setVar <- forAll (standaloneGen $ variableGen setSort)
            Monad.when (variableName elementVar == variableName setVar) discard
            let fnSelectPat    = selectFunctionPattern elementVar setVar id
                fnSelectPatRev = selectFunctionPattern elementVar setVar reverse
                singleton      = asInternal (Set.singleton concreteElem)
                elemStepPatt   = fromConcrete concreteElem
                elementVarPatt = mkApplySymbol absIntSymbol [mkVar elementVar]
                expect = do  -- list monad
                    expectedSet <- [[], [concreteElem]]
                    return Conditional
                        { term = singleton
                        , predicate =
                            makeEqualsPredicate elemStepPatt elementVarPatt
                        , substitution =
                            Substitution.unsafeWrap
                                [   ( setVar
                                    , asInternal (Set.fromList expectedSet)
                                    )
                                ]
                        }
            -- { 5 } /\ SetItem(absInt(X:Int)) Rest:Set
            (singleton `unifiesWithMulti` fnSelectPat) expect
            (fnSelectPat `unifiesWithMulti` singleton) expect
            -- { 5 } /\ Rest:Set SetItem(absInt(X:Int))
            (singleton `unifiesWithMulti` fnSelectPatRev) expect
            (fnSelectPatRev `unifiesWithMulti` singleton) expect
         )

{- | Unify a concrete Set with symbolic-keyed Set.

@
(1, [1]) ∧ (x, [x])
@

Iterated unification must turn the symbolic key @x@ into a concrete key by
unifying the first element of the pair. This also requires that Set unification
return a partial result for unifying the second element of the pair.

 -}
test_concretizeKeys :: TestTree
test_concretizeKeys =
    testCaseWithSMT "unify Set with symbolic keys" $ do
        actual <- evaluate original
        assertEqualWithExplanation "" expected actual
  where
    x =
        Variable
            { variableName = testId "x"
            , variableCounter = mempty
            , variableSort = intSort
            }
    key = 1
    symbolicKey = Test.Int.asInternal key
    concreteKey = Test.Int.asInternal key
    concreteSet = asTermLike $ Set.fromList [concreteKey]
    symbolic = asSymbolicPattern $ Set.fromList [mkVar x]
    original =
        mkAnd
            (mkPair intSort setSort (Test.Int.asInternal 1) concreteSet)
            (mkPair intSort setSort (mkVar x) symbolic)
    expected =
        Conditional
            { term =
                mkPair intSort setSort
                    symbolicKey
                    (asInternal $ Set.fromList [concreteKey])
            , predicate = Predicate.makeTruePredicate
            , substitution = Substitution.unsafeWrap
                [ (x, symbolicKey) ]
            }

{- | Unify a concrete Set with symbolic-keyed Set in an axiom

Apply the axiom
@
(x, [x]) => x
@
to the configuration
@
(1, [1])
@
yielding @1@.

Iterated unification must turn the symbolic key @x@ into a concrete key by
unifying the first element of the pair. This also requires that Set unification
return a partial result for unifying the second element of the pair.

 -}
test_concretizeKeysAxiom :: TestTree
test_concretizeKeysAxiom =
    testCaseWithSMT "unify Set with symbolic keys in axiom" $ do
        let pair = mkPair intSort setSort symbolicKey concreteSet
        config <- evaluate pair
        actual <- runStep config axiom
        assertEqualWithExplanation "" expected actual
  where
    x = mkIntVar (testId "x")
    key = 1
    symbolicKey = Test.Int.asInternal key
    concreteKey = Test.Int.asInternal key
    symbolicSet = asSymbolicPattern $ Set.fromList [x]
    concreteSet = asTermLike $ Set.fromList [concreteKey]
    axiom =
        RewriteRule RulePattern
            { left = mkPair intSort setSort x symbolicSet
            , right = x
            , requires = Predicate.makeTruePredicate
            , ensures = Predicate.makeTruePredicate
            , attributes = Default.def
            }
    expected = Right (MultiOr [ pure symbolicKey ])

test_isBuiltin :: [TestTree]
test_isBuiltin =
    [ testCase "isSymbolConcat" $ do
        assertBool ""
            (Set.isSymbolConcat mockHookTools Mock.concatSetSymbol)
        assertBool ""
            (not (Set.isSymbolConcat mockHookTools Mock.aSymbol))
        assertBool ""
            (not (Set.isSymbolConcat mockHookTools Mock.elementSetSymbol))
    , testCase "isSymbolElement" $ do
        assertBool ""
            (Set.isSymbolElement mockHookTools Mock.elementSetSymbol)
        assertBool ""
            (not (Set.isSymbolElement mockHookTools Mock.aSymbol))
        assertBool ""
            (not (Set.isSymbolElement mockHookTools Mock.concatSetSymbol))
    , testCase "isSymbolUnit" $ do
        assertBool ""
            (Set.isSymbolUnit mockHookTools Mock.unitSetSymbol)
        assertBool ""
            (not (Set.isSymbolUnit mockHookTools Mock.aSymbol))
        assertBool ""
            (not (Set.isSymbolUnit mockHookTools Mock.concatSetSymbol))
    ]

hprop_unparse :: Property
hprop_unparse = hpropUnparse (asInternal <$> genConcreteSet)

mockHookTools :: SmtMetadataTools Hook
mockHookTools = StepperAttributes.hook <$> Mock.metadataTools

-- | Specialize 'Set.asTermLike' to the builtin sort 'setSort'.
asTermLike
    :: Foldable f
    => f (TermLike Concrete)
    -> TermLike Variable
asTermLike =
    Reflection.give testMetadataTools Set.asTermLike
    . builtinSet
    . Foldable.toList

-- | Specialize 'Set.asPattern' to the builtin sort 'setSort'.
asPattern :: Set (TermLike Concrete) -> Pattern Variable
asPattern = Reflection.give testMetadataTools Set.asPattern setSort

-- | Specialize 'Set.builtinSet' to the builtin sort 'setSort'.
asInternal :: Set (TermLike Concrete) -> TermLike Variable
asInternal = Set.asInternal testMetadataTools setSort

-- * Constructors

mkIntVar :: Id -> TermLike Variable
mkIntVar variableName =
    mkVar
        Variable
            { variableName, variableCounter = mempty, variableSort = intSort }
