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
import qualified Data.Default as Default
import qualified Data.Foldable as Foldable
import qualified Data.Reflection as Reflection
import qualified Data.Sequence as Seq
import           Data.Set
                 ( Set )
import qualified Data.Set as Set

import           Kore.Attribute.Hook
                 ( Hook )
import           Kore.Attribute.Symbol
                 ( StepperAttributes )
import qualified Kore.Attribute.Symbol as StepperAttributes
import qualified Kore.Builtin.Set as Set
import           Kore.IndexedModule.MetadataTools
                 ( SmtMetadataTools )
import           Kore.Internal.MultiOr
                 ( MultiOr (..) )
import           Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
import           Kore.Predicate.Predicate as Predicate
import           Kore.Step.Rule
                 ( RewriteRule (RewriteRule), RulePattern (RulePattern) )
import           Kore.Step.Rule as RulePattern
                 ( RulePattern (..) )
import qualified Kore.Unification.Substitution as Substitution
import qualified SMT


import           Test.Kore
import qualified Test.Kore.Builtin.Bool as Test.Bool
import           Test.Kore.Builtin.Builtin
import           Test.Kore.Builtin.Definition
import           Test.Kore.Builtin.Int
                 ( genConcreteIntegerPattern, genInteger, genIntegerPattern )
import qualified Test.Kore.Builtin.Int as Test.Int
import qualified Test.Kore.Builtin.List as Test.List
import           Test.Kore.Comparators ()
import qualified Test.Kore.IndexedModule.MockMetadataTools as Mock
                 ( makeMetadataTools )
import qualified Test.Kore.Step.MockSymbols as Mock
import           Test.SMT
import           Test.Tasty.HUnit.Extensions

genSetInteger :: Gen (Set Integer)
genSetInteger = Gen.set (Range.linear 0 32) genInteger

genSetConcreteIntegerPattern :: Gen (Set (TermLike Concrete))
genSetConcreteIntegerPattern =
    Set.map Test.Int.asInternal <$> genSetInteger

genConcreteSet :: Gen Set.Builtin
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
                    mkApp
                        boolSort
                        inSetSymbol
                        [ patKey
                        , mkApp setSort unitSetSymbol []
                        ]
                patFalse = Test.Bool.asInternal False
                predicate = mkEquals_ patFalse patIn
            (===) (Test.Bool.asPattern False) =<< evaluate patIn
            (===) Pattern.top =<< evaluate predicate
        )

test_inElement :: TestTree
test_inElement =
    testPropertyWithSolver
        "in{}(x, element{}(x)) === \\dv{Bool{}}(\"true\")"
        (do
            patKey <- forAll genIntegerPattern
            let patIn = mkApp boolSort inSetSymbol [ patKey, patElement ]
                patElement = mkApp setSort elementSetSymbol [ patKey ]
                patTrue = Test.Bool.asInternal True
                predicate = mkEquals_ patIn patTrue
            (===) (Test.Bool.asPattern True) =<< evaluate patIn
            (===) Pattern.top =<< evaluate predicate
        )

test_inConcat :: TestTree
test_inConcat =
    testPropertyWithSolver
        "in{}(concat{}(_, element{}(e)), e) === \\dv{Bool{}}(\"true\")"
        (do
            elem' <- forAll genConcreteIntegerPattern
            values <- forAll genSetConcreteIntegerPattern
            let patIn = mkApp boolSort inSetSymbol [ patElem , patSet ]
                patSet = asTermLike $ Set.insert elem' values
                patElem = fromConcreteStepPattern elem'
                patTrue = Test.Bool.asInternal True
                predicate = mkEquals_ patTrue patIn
            (===) (Test.Bool.asPattern True) =<< evaluate patIn
            (===) Pattern.top =<< evaluate predicate
        )

test_concatUnit :: TestTree
test_concatUnit =
    testPropertyWithSolver
        "concat{}(unit{}(), xs) === concat{}(xs, unit{}()) === xs"
        (do
            patValues <- forAll genSetPattern
            let patUnit = mkApp setSort unitSetSymbol []
                patConcat1 =
                    mkApp setSort concatSetSymbol [ patUnit, patValues ]
                patConcat2 =
                    mkApp setSort concatSetSymbol [ patValues, patUnit ]
                predicate1 = mkEquals_ patValues patConcat1
                predicate2 = mkEquals_ patValues patConcat2
            expect <- evaluate patValues
            (===) expect =<< evaluate patConcat1
            (===) expect =<< evaluate patConcat2
            (===) Pattern.top =<< evaluate predicate1
            (===) Pattern.top =<< evaluate predicate2
        )

test_concatAssociates :: TestTree
test_concatAssociates =
    testPropertyWithSolver
        "concat{}(concat{}(as, bs), cs) === concat{}(as, concat{}(bs, cs))"
        (do
            patSet1 <- forAll genSetPattern
            patSet2 <- forAll genSetPattern
            patSet3 <- forAll genSetPattern
            let patConcat12 = mkApp setSort concatSetSymbol [ patSet1, patSet2 ]
                patConcat23 = mkApp setSort concatSetSymbol [ patSet2, patSet3 ]
                patConcat12_3 = mkApp setSort concatSetSymbol [ patConcat12, patSet3 ]
                patConcat1_23 = mkApp setSort concatSetSymbol [ patSet1, patConcat23 ]
                predicate = mkEquals_ patConcat12_3 patConcat1_23
            concat12_3 <- evaluate patConcat12_3
            concat1_23 <- evaluate patConcat1_23
            (===) concat12_3 concat1_23
            (===) Pattern.top =<< evaluate predicate
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
                    mkApp
                        setSort
                        differenceSetSymbol
                        [ asTermLike set1, asTermLike set2 ]
                predicate = mkEquals_ patSet3 patDifference
            expect <- evaluate patSet3
            (===) expect =<< evaluate patDifference
            (===) Pattern.top =<< evaluate predicate
        )

test_toList :: TestTree
test_toList =
    testPropertyWithSolver
        "SET.set2list is set2list"
        (do
            set1 <- forAll genSetConcreteIntegerPattern
            let set2 =
                    fmap fromConcreteStepPattern
                    . Seq.fromList . Set.toList $ set1
                patSet2 = Test.List.asTermLike set2
                patToList =
                    mkApp
                        listSort
                        toListSetSymbol
                        [ asTermLike set1 ]
                predicate = mkEquals_ patSet2 patToList
            expect <- evaluate patSet2
            (===) expect =<< evaluate patToList
            (===) Pattern.top =<< evaluate predicate
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
                    mkApp
                        intSort
                        sizeSetSymbol
                        [ asTermLike set ]
                predicate = mkEquals_ patExpected patActual
            expect <- evaluate patExpected
            (===) expect =<< evaluate patActual
            (===) Pattern.top =<< evaluate predicate
        )

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
                else (===) expect =<< evaluate patMap
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
    applyUnit = mkApp setSort unitSetSymbol []
    applyElement key = mkApp setSort elementSetSymbol [key]
    applyConcat set1 set2 = mkApp setSort concatSetSymbol [set1, set2]

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
            expect <- evaluate patSet
            (===) expect =<< evaluate patAnd
            (===) Pattern.top =<< evaluate predicate
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
            (===) Pattern.bottom =<< evaluate conjunction
            (===) Pattern.bottom =<< evaluate predicate
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
                    mkApp setSort concatSetSymbol
                        [ asTermLike framedSet
                        , mkVar frameVar
                        ]
                remainder = Set.delete framedElem concreteSet
            let
                expect =
                    Conditional
                        { term = asInternal concreteSet
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [(frameVar, asInternal remainder)]
                        }
            (===) expect =<< evaluate (mkAnd patConcreteSet patFramedSet)
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
    mkApp setSort concatSetSymbol $ permutation [singleton, mkVar setVar]
  where
    element = mkApp intSort absIntSymbol  [mkVar elementVar]
    singleton = mkApp setSort elementSetSymbol [ element ]

-- Given a function to scramble the arguments to concat, i.e.,
-- @id@ or @reverse@, produces a pattern of the form
-- `SetItem(X:Int) Rest:Set`, or `Rest:Set SetItem(X:Int)`, respectively.
selectPattern
    :: Variable          -- ^element variable
    -> Variable          -- ^set variable
    -> (forall a . [a] -> [a])  -- ^scrambling function
    -> TermLike Variable
selectPattern elementVar setVar permutation  =
    mkApp setSort concatSetSymbol $ permutation [element, mkVar setVar]
  where
    element = mkApp setSort elementSetSymbol [mkVar elementVar]

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
    doesNotUnifyWith pat1 pat2 =
            (===) Pattern.bottom =<< evaluate (mkAnd pat1 pat2)

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
                elemStepPattern = fromConcreteStepPattern concreteElem
                expect =
                    Conditional
                        { term = singleton
                        , predicate = makeTruePredicate
                        , substitution =
                            Substitution.unsafeWrap
                                [ (setVar, asInternal Set.empty)
                                , (elementVar, elemStepPattern)
                                ]
                        }
            -- { 5 } /\ SetItem(X:Int) Rest:Set
            (singleton `unifiesWith` selectPat) expect
            (selectPat `unifiesWith` singleton) expect
            -- { 5 } /\ Rest:Set SetItem(X:Int)
            (singleton `unifiesWith` selectPatRev) expect
            (selectPatRev `unifiesWith` singleton) expect
        )

-- use as (pat1 `unifiesWith` pat2) expect
unifiesWith
    :: HasCallStack
    => TermLike Variable
    -> TermLike Variable
    -> Pattern Variable
    -> PropertyT SMT.SMT ()
unifiesWith pat1 pat2 Conditional { term, predicate, substitution } = do
    Conditional { term = uTerm, predicate = uPred, substitution = uSubst } <-
        evaluate (mkAnd pat1 pat2)
    Substitution.toMap substitution === Substitution.toMap uSubst
    predicate === uPred
    term === uTerm

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
                elemStepPatt = fromConcreteStepPattern concreteElem
                elementVarPatt = mkApp intSort absIntSymbol  [mkVar elementVar]
                expect =
                    Conditional
                        { term = singleton
                        , predicate =
                            makeEqualsPredicate elemStepPatt elementVarPatt
                        , substitution =
                            Substitution.unsafeWrap
                                [ (setVar, asInternal Set.empty) ]
                        }
            -- { 5 } /\ SetItem(absInt(X:Int)) Rest:Set
            (singleton `unifiesWith` fnSelectPat) expect
            (fnSelectPat `unifiesWith` singleton) expect
            -- { 5 } /\ Rest:Set SetItem(absInt(X:Int))
            (singleton `unifiesWith` fnSelectPatRev) expect
            (fnSelectPatRev `unifiesWith` singleton) expect
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
    testCaseWithSolver "unify Set with symbolic keys" $ \solver -> do
        actual <- evaluateWith solver original
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
                    (asSymbolicPattern $ Set.fromList [symbolicKey])
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
    testCaseWithSolver "unify Set with symbolic keys in axiom" $ \solver -> do
        let pair = mkPair intSort setSort symbolicKey concreteSet
        config <- evaluateWith solver pair
        actual <- runStepWith solver config axiom
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

mockMetadataTools :: SmtMetadataTools StepperAttributes
mockMetadataTools =
    Mock.makeMetadataTools
        Mock.attributesMapping
        Mock.headTypeMapping
        Mock.sortAttributesMapping
        Mock.subsorts
        Mock.headSortsMapping
        Mock.smtDeclarations

mockHookTools :: SmtMetadataTools Hook
mockHookTools = StepperAttributes.hook <$> mockMetadataTools

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
asPattern :: Set.Builtin -> Pattern Variable
asPattern =
    Reflection.give testMetadataTools Set.asPattern setSort

-- | Specialize 'Set.builtinSet' to the builtin sort 'setSort'.
asInternal :: Set.Builtin -> TermLike Variable
asInternal = Set.asInternal testMetadataTools setSort

-- * Constructors

mkIntVar :: Id -> TermLike Variable
mkIntVar variableName =
    mkVar Variable { variableName, variableCounter = mempty, variableSort = intSort }
