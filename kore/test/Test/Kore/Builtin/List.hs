module Test.Kore.Builtin.List
    ( test_getUnit
    , test_getFirstElement
    , test_getLastElement
    , test_GetUpdate
    , test_concatUnit
    , test_concatUnitSymbolic
    , test_concatAssociates
    , test_concatHeadTailSymbolic
    , test_simplify
    , test_isBuiltin
    , test_inUnit
    , test_inElement
    , test_inConcat
    , hprop_unparse
    , test_size
    --
    , asInternal
    , asTermLike
    , genSeqInteger
    ) where
import Prelude.Kore

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty
import Test.Tasty.HUnit

import qualified Control.Lens as Lens
import qualified Data.Foldable as Foldable
import Data.List
    ( sort
    )
import qualified Data.Reflection as Reflection
import Data.Sequence
    ( Seq
    )
import Data.Generics.Product
    ( field
    )
import qualified Data.Sequence as Seq
import qualified Data.Map.Strict as Map
import GHC.Exts
    ( fromList
    )

import qualified Kore.Attribute.Pattern as Attribute
import Kore.Attribute.Pattern.Simplified
import Kore.Attribute.Pattern.ConstructorLike
    ( ConstructorLike (..)
    , ConstructorLikeHead (..)
    )
import qualified Kore.Builtin.List as List
import Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeTruePredicate
    )
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
import Kore.Variables.UnifiedVariable
    ( UnifiedVariable (..)
    )
import SMT
    ( SMT
    )

import Test.Kore
    ( testId
    )
import qualified Test.Kore.Builtin.Bool as Test.Bool
import Test.Kore.Builtin.Builtin
import Test.Kore.Builtin.Definition
import qualified Test.Kore.Builtin.Int as Test.Int
import qualified Test.Kore.Step.MockSymbols as Mock
import Test.SMT

import Kore.Unparser
import Kore.Syntax.Variable as Variable
import qualified Kore.Builtin.AssociativeCommutative as Ac
import qualified Kore.Domain.Builtin as Domain
import Test.Kore.With

genInteger :: Gen Integer
genInteger = Gen.integral (Range.linear (-1024) 1024)

genSeqInteger :: Gen (Seq Integer)
genSeqInteger = Gen.seq (Range.linear 0 16) genInteger

genSeqIndex :: Gen Integer
genSeqIndex = Gen.integral (Range.linear (-20) 20)

test_getUnit :: TestTree
test_getUnit =
    testPropertyWithSolver "get{}(unit{}(), _) === \\bottom{}()" $ do
        k <- forAll genInteger
        let patGet =
                mkApplySymbol getListSymbol
                    [ mkApplySymbol unitListSymbol []
                    , Test.Int.asInternal k
                    ]
            predicate = mkEquals_ mkBottom_ patGet
        (===) Pattern.bottom =<< evaluateT patGet
        (===) Pattern.top    =<< evaluateT predicate

test_getFirstElement :: TestTree
test_getFirstElement =
    testPropertyWithSolver
        "get{}(concat{}(element{}(e), _), 0) === e"
        prop
  where
    prop = do
        values <- forAll genSeqInteger
        let patGet =
                mkApplySymbol getListSymbol [ patList , Test.Int.asInternal 0 ]
            patList = asTermLike (Test.Int.asInternal <$> values)
            value =
                case values of
                    Seq.Empty -> Nothing
                    v Seq.:<| _ -> Just v
            patFirst = maybe mkBottom_ Test.Int.asInternal value
            predicate = mkEquals_ patGet patFirst
        let expectGet = Test.Int.asPartialPattern value
        (===) expectGet   =<< evaluateT patGet
        (===) Pattern.top =<< evaluateT predicate

test_getLastElement :: TestTree
test_getLastElement =
    testPropertyWithSolver
        "get{}(concat{}(_, element{}(e)), -1) === e"
        prop
  where
    prop = do
        values <- forAll genSeqInteger
        let patGet =
                mkApplySymbol
                    getListSymbol
                    [ patList , Test.Int.asInternal (-1) ]
            patList = asTermLike (Test.Int.asInternal <$> values)
            value =
                case values of
                    Seq.Empty -> Nothing
                    _ Seq.:|> v -> Just v
            patFirst = maybe mkBottom_ Test.Int.asInternal value
            predicate = mkEquals_ patGet patFirst
        let expectGet = Test.Int.asPartialPattern value
        (===) expectGet   =<< evaluateT patGet
        (===) Pattern.top =<< evaluateT predicate

test_GetUpdate :: TestTree
test_GetUpdate =
    testPropertyWithSolver
    "get{}(update{}(map, ix, val), ix) === val"
    prop
  where
    prop = do
        values <- forAll genSeqInteger
        value  <- forAll Test.Int.genIntegerPattern
        ix <- forAll genSeqIndex
        let len = fromIntegral $ length values
            patValues = asTermLike $ Test.Int.asInternal <$> values
            patUpdated = updateList patValues (Test.Int.asInternal ix) value
        if (-len) <= ix && ix < len then do
            let patGet = getList patUpdated $ Test.Int.asInternal ix
                predicate = mkEquals_
                    patGet
                    value
                expect = Pattern.fromTermLike value
            (===) Pattern.top  =<< evaluateT predicate
            (===) expect =<< evaluateT patGet
        else do
            let predicate = mkEquals_ mkBottom_ patUpdated
            (===) Pattern.bottom =<< evaluateT patUpdated
            (===) Pattern.top =<< evaluateT predicate

test_inUnit :: TestTree
test_inUnit =
    testPropertyWithSolver
    "in{}(x, unit{}()) === \\dv{Bool{}}(\"false\")"
    prop
  where
    prop = do
        value <- forAll genInteger
        let patValue = Test.Int.asInternal value
            patIn = inList patValue unitList
            patFalse = Test.Bool.asInternal False
            predicate = mkEquals_ patFalse patIn
        (===) (Test.Bool.asPattern False) =<< evaluateT patIn
        (===) Pattern.top =<< evaluateT predicate

test_inElement :: TestTree
test_inElement =
    testPropertyWithSolver
    "in{}(x, element{}(x)) === \\dv{Bool{}}(\"true\")"
    prop
  where
    prop = do
        value <- forAll genInteger
        let patValue = Test.Int.asInternal value
            patElement = elementList patValue
            patIn = inList patValue patElement
            patTrue = Test.Bool.asInternal True
            predicate = mkEquals_ patIn patTrue
        (===) (Test.Bool.asPattern True) =<< evaluateT patIn
        (===) Pattern.top =<< evaluateT predicate

test_inConcat :: TestTree
test_inConcat =
    testPropertyWithSolver
    "in{}(x, concat{}(list, element{}(x))) === \\dv{Bool{}}(\"true\")"
    prop
  where
    prop = do
        value <- forAll genInteger
        values <- forAll genSeqInteger
        let patValue = Test.Int.asInternal value
            patValues = asTermLike (Test.Int.asInternal <$> values)
            patElement = elementList patValue
            patConcat = concatList patValues patElement
            patIn = inList patValue patConcat
            patTrue = Test.Bool.asInternal True
            predicate = mkEquals_ patIn patTrue
        (===) (Test.Bool.asPattern True) =<< evaluateT patIn
        (===) Pattern.top =<< evaluateT predicate

test_concatUnit :: TestTree
test_concatUnit =
    testPropertyWithSolver
        "concat{}(unit{}(), xs) === concat{}(xs, unit{}()) === xs"
        prop
  where
    prop = do
        values <- forAll genSeqInteger
        let patUnit = mkApplySymbol unitListSymbol []
            patValues = asTermLike (Test.Int.asInternal <$> values)
            patConcat1 = mkApplySymbol concatListSymbol [ patUnit, patValues ]
            patConcat2 = mkApplySymbol concatListSymbol [ patValues, patUnit ]
            predicate1 = mkEquals_ patValues patConcat1
            predicate2 = mkEquals_ patValues patConcat2
        expectValues <- evaluateT patValues
        (===) expectValues =<< evaluateT patConcat1
        (===) expectValues =<< evaluateT patConcat2
        (===) Pattern.top  =<< evaluateT predicate1
        (===) Pattern.top  =<< evaluateT predicate2

test_concatUnitSymbolic :: TestTree
test_concatUnitSymbolic =
    testPropertyWithSolver
        "concat{}(unit{}(), x) === concat{}(xs, unit{}()) === x"
        prop
  where
    prop = do
        let patUnit = mkApplySymbol unitListSymbol []
            patSymbolic = mkElemVar $ ElementVariable Variable
                { variableName = testId "x"
                , variableCounter = mempty
                , variableSort = listSort
                }
            patConcat1 = mkApplySymbol concatListSymbol [ patUnit, patSymbolic ]
            patConcat2 = mkApplySymbol concatListSymbol [ patSymbolic, patUnit ]
            predicate1 = mkEquals_ patSymbolic patConcat1
            predicate2 = mkEquals_ patSymbolic patConcat2
        expectSymbolic <- evaluateT patSymbolic
        (===) expectSymbolic =<< evaluateT patConcat1
        (===) expectSymbolic =<< evaluateT patConcat2
        (===) Pattern.top  =<< evaluateT predicate1
        (===) Pattern.top  =<< evaluateT predicate2

test_concatAssociates :: TestTree
test_concatAssociates =
    testPropertyWithSolver
        "concat{}(concat{}(as, bs), cs) === concat{}(as, concat{}(bs, cs))"
        prop
  where
    prop = do
        values1 <- forAll genSeqInteger
        values2 <- forAll genSeqInteger
        values3 <- forAll genSeqInteger
        let patList1 = asTermLike $ Test.Int.asInternal <$> values1
            patList2 = asTermLike $ Test.Int.asInternal <$> values2
            patList3 = asTermLike $ Test.Int.asInternal <$> values3
            patConcat12 = mkApplySymbol concatListSymbol [ patList1, patList2 ]
            patConcat23 = mkApplySymbol concatListSymbol [ patList2, patList3 ]
            patConcat12_3 =
                mkApplySymbol concatListSymbol [ patConcat12, patList3 ]
            patConcat1_23 =
                mkApplySymbol concatListSymbol [ patList1, patConcat23 ]
            predicate = mkEquals_ patConcat12_3 patConcat1_23
        evalConcat12_3 <- evaluateT patConcat12_3
        evalConcat1_23 <- evaluateT patConcat1_23
        (===) evalConcat12_3 evalConcat1_23
        (===) Pattern.top =<< evaluateT predicate

test_concatHeadTailSymbolic :: TestTree
test_concatHeadTailSymbolic =
    testPropertyWithSolver
        "qqand{}(concat{}(element{}(x), xs), concat{}(element{}(y), ys)) ===\
        \ \\dv{Bool{}}(\"true\")"
        prop
  where
    prop = do
        let elemVarX = ElementVariable Variable
                { variableName = testId "x"
                , variableCounter = mempty
                , variableSort = intSort
                }
            patSymbolicX = mkElemVar elemVarX
            elemVarY = ElementVariable Variable
                { variableName = testId "y"
                , variableCounter = mempty
                , variableSort = intSort
                }
            patSymbolicY = mkElemVar elemVarY
            elemVarXs = ElementVariable Variable
                { variableName = testId "xs"
                , variableCounter = mempty
                , variableSort = listSort
                }
            patSymbolicXs = mkElemVar elemVarXs
            elemVarYs = ElementVariable Variable
                { variableName = testId "ys"
                , variableCounter = mempty
                , variableSort = listSort
                }
            patSymbolicYs = mkElemVar elemVarYs
            patElemX = elementList patSymbolicX
            patElemY = elementList patSymbolicY
            patConcatX =
                mkApplySymbol concatListSymbol [ patElemX, patSymbolicXs ]
            patConcatY =
                mkApplySymbol concatListSymbol [ patElemY, patSymbolicYs ]
            patUnifiedXY = mkAnd patConcatX patConcatY
            expect = Conditional
                        { term = patConcatY
                        , predicate = makeTruePredicate listSort
                        , substitution =
                            from $ Map.fromList
                                [ (ElemVar elemVarX, patSymbolicY)
                                , (ElemVar elemVarXs, patSymbolicYs)
                                ]
                        }
        unified <- evaluateT patUnifiedXY
        traceM $ "Expect\n" <> unparseToString expect
        traceM $ "UnifiedResult\n" <> unparseToString unified
        --traceM $ "UnifiedXY\n" <> unparseToString patUnifiedXY
        --(patConcatX `unifiesWith` patConcatY) expect
        (===)
            expect
            $ unified 
            & Lens.over
                (field @"term" . field @"getTermLike")
                (fmap irrelevantPattern)
    irrelevantPattern
        (Attribute.Pattern sort fv _ _ _ _ simplified constructorLike)
      =
        Attribute.Pattern
            sort
            fv
            (Attribute.Functional False)
            (Attribute.Function False)
            (Attribute.Defined False)
            (Attribute.Created (Just $ fromList []))
            NotSimplified
            constructorLike

-- | Check that simplification is carried out on list elements.
test_simplify :: TestTree
test_simplify =
    testPropertyWithSolver "simplify elements" $ do
        let
            x =
                mkElemVar $ ElementVariable Variable
                    { variableName = testId "x"
                    , variableCounter = mempty
                    , variableSort = intSort
                    }
            original = asInternal [mkAnd x mkTop_]
            expected = asPattern [x]
        (===) expected =<< evaluateT original

test_isBuiltin :: [TestTree]
test_isBuiltin =
    [ testCase "isSymbolConcat" $ do
        assertBool "" (List.isSymbolConcat Mock.concatListSymbol)
        assertBool "" (not (List.isSymbolConcat Mock.aSymbol))
        assertBool "" (not (List.isSymbolConcat Mock.elementListSymbol))
    , testCase "isSymbolElement" $ do
        assertBool "" (List.isSymbolElement Mock.elementListSymbol)
        assertBool "" (not (List.isSymbolElement Mock.aSymbol))
        assertBool "" (not (List.isSymbolElement Mock.concatListSymbol))
    , testCase "isSymbolUnit" $ do
        assertBool "" (List.isSymbolUnit Mock.unitListSymbol)
        assertBool "" (not (List.isSymbolUnit Mock.aSymbol))
        assertBool "" (not (List.isSymbolUnit Mock.concatListSymbol))
    ]

test_size :: [TestTree]
test_size =
    [ testPropertyWithSolver "size(unit(_)) = 0" $ do
        let original = sizeList unitList
            zero = mkInt 0
            predicate = mkEquals_ zero original
        (===) (Pattern.fromTermLike zero) =<< evaluateT original
        (===) Pattern.top                      =<< evaluateT predicate
    , testPropertyWithSolver "size(element(_)) = 1" $ do
        k <- forAll genInteger
        let original = sizeList (elementList $ mkInt k)
            one = mkInt 1
            predicate = mkEquals_ one original
        (===) (Pattern.fromTermLike one) =<< evaluateT original
        (===) Pattern.top                =<< evaluateT predicate
    , testPropertyWithSolver "size(a + b) = size(a) + size(b)" $ do
        as <- asInternal . fmap mkInt <$> forAll genSeqInteger
        bs <- asInternal . fmap mkInt <$> forAll genSeqInteger
        let sizeConcat = sizeList (concatList as bs)
            addSize = addInt (sizeList as) (sizeList bs)
            predicate = mkEquals_ sizeConcat addSize
        expect1 <- evaluateT sizeConcat
        expect2 <- evaluateT addSize
        (===) expect1 expect2
        (===) Pattern.top    =<< evaluateT predicate
    ]

mkInt :: Integer -> TermLike Variable
mkInt = Test.Int.asInternal

-- | Specialize 'List.asPattern' to the builtin sort 'listSort'.
asTermLike
    :: Foldable f
    => f (TermLike Variable)
    -> TermLike Variable
asTermLike =
    Reflection.give testMetadataTools List.asTermLike
    . builtinList
    . Foldable.toList

-- | Specialize 'List.asInternal' to the builtin sort 'listSort'.
asInternal
    :: Foldable f
    => f (TermLike Variable)
    -> TermLike Variable
asInternal =
    List.asInternal testMetadataTools listSort
    . Seq.fromList
    . Foldable.toList

-- | Specialize 'List.asPattern' to the builtin sort 'listSort'.
asPattern
    :: Foldable f
    => f (TermLike Variable)
    -> Pattern Variable
asPattern =
    Reflection.give testMetadataTools List.asPattern listSort
    . Seq.fromList
    . Foldable.toList

hprop_unparse :: Property
hprop_unparse =
    hpropUnparse (asInternal . (<$>) Test.Int.asInternal <$> genSeqInteger)

-- use as (pat1 `unifiesWith` pat2) expect
unifiesWith
    :: HasCallStack
    => TermLike Variable
    -> TermLike Variable
    -> Pattern Variable
    -> PropertyT SMT ()
unifiesWith pat1 pat2 expected =
    unifiesWithMulti pat1 pat2 [expected]

-- use as (pat1 `unifiesWithMulti` pat2) expect
unifiesWithMulti
    :: HasCallStack
    => TermLike Variable
    -> TermLike Variable
    -> [Pattern Variable]
    -> PropertyT SMT ()
unifiesWithMulti pat1 pat2 expectedResults = do
    actualResults <- lift $ evaluateToList (mkAnd pat1 pat2)
    compareElements (sort expectedResults) actualResults
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
