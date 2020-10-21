module Test.Kore.Builtin
    ( test_internalize
    , test_sortModuleClaims
    ) where

import Prelude.Kore hiding
    ( concatMap
    )

import Test.Tasty
import Test.Tasty.HUnit

import Control.Lens
    ( ix
    , (%~)
    , (.~)
    )
import qualified Control.Lens as Lens
import Data.Generics.Product
    ( field
    )
import qualified Data.Set

import Kore.ASTVerifier.DefinitionVerifier
    ( sortModuleClaims
    )
import Kore.Attribute.Axiom
    ( SourceLocation
    )
import qualified Kore.Attribute.Symbol as Attribute
import qualified Kore.Builtin as Kore
import Kore.IndexedModule.IndexedModule
    ( IndexedModule (..)
    , VerifiedModule
    )
import Kore.IndexedModule.MetadataTools
    ( SmtMetadataTools
    )
import Kore.Internal.TermLike
import Test.Kore.Step.SMT.Builders
    ( indexModule
    )

import qualified Test.Kore.Builtin.Builtin as Builtin
import qualified Test.Kore.Builtin.Definition as Builtin
import qualified Test.Kore.Builtin.Int as Int
import qualified Test.Kore.Builtin.List as List
import qualified Test.Kore.Builtin.Map as Map
import qualified Test.Kore.Builtin.Set as Set

test_internalize :: [TestTree]
test_internalize =
    [ internalizes  "unitList"
        unitList
        (mkList [])
    , internalizes  "elementList"
        (elementList x)
        (mkList [x])
    , internalizes  "concatList(internal, internal)"
        (concatList (mkList [x]) (mkList [y]))
        (mkList [x, y])
    , internalizes  "concatList(element, element)"
        (concatList (elementList x) (elementList y))
        (mkList [x, y])
    , internalizes  "concatList(element, unit)"
        (concatList (elementList x) unitList)
        (mkList [x])
    , internalizes  "concatList(unit, element)"
        (concatList unitList (elementList y))
        (mkList [y])
    , notInternalizes "l:List" l
    , internalizes "concatList(l:List, unit)" (concatList l unitList) l
    , internalizes "concatList(unit, l:List)" (concatList unitList l) l

    , internalizes  "unitMap"
        unitMap
        (mkMap [])
    , internalizes  "elementMap"
        (elementMap zero x)
        (mkMap [(zero, x)])
    , internalizes  "concatMap(internal, internal)"
        (concatMap (mkMap [(zero, x)]) (mkMap [(one, y)]))
        (mkMap [(zero, x), (one, y)])
    , internalizes  "concatMap(element, element)"
        (concatMap (elementMap zero x) (elementMap one y))
        (mkMap [(zero, x), (one, y)])
    , internalizes  "concatMap(element, unit)"
        (concatMap (elementMap zero x) unitMap)
        (mkMap [(zero, x)])
    , internalizes  "concatMap(unit, element)"
        (concatMap unitMap (elementMap one y))
        (mkMap [(one, y)])
    , notInternalizes "m:Map" m
    , internalizes "concatMap(m:Map, unit)" (concatMap m unitMap) m
    , internalizes "concatMap(unit, m:Map)" (concatMap unitMap m) m

    , internalizes  "unitSet"
        unitSet
        (mkSet [])
    , internalizes  "elementSet"
        (elementSet zero)
        (mkSet [zero])
    , internalizes  "concatSet(internal, internal)"
        (concatSet (mkSet [zero]) (mkSet [one]))
        (mkSet [zero, one])
    , internalizes  "concatSet(element, element)"
        (concatSet (elementSet zero) (elementSet one))
        (mkSet [zero, one])
    , internalizes  "concatSet(element, unit)"
        (concatSet (elementSet zero) unitSet)
        (mkSet [zero])
    , internalizes  "concatSet(unit, element)"
        (concatSet unitSet (elementSet one))
        (mkSet [one])
    , notInternalizes "s:Set" s
    , internalizes "concatSet(s:Set, unit)" (concatSet s unitSet) s
    , internalizes "concatSet(unit, s:Set)" (concatSet unitSet s) s
    ]
  where
    listSort = Builtin.listSort
    unitList = Builtin.unitList
    elementList = Builtin.elementList
    concatList = Builtin.concatList
    mkList = List.asInternal
    l = mkElemVar (mkElementVariable "l" listSort)

    mapSort = Builtin.mapSort
    unitMap = Builtin.unitMap
    elementMap = Builtin.elementMap
    concatMap = Builtin.concatMap
    mkMap = Map.asInternal
    m = mkElemVar (mkElementVariable "m" mapSort)

    setSort = Builtin.setSort
    unitSet = Builtin.unitSet
    elementSet = Builtin.elementSet
    concatSet = Builtin.concatSet
    mkSet = Set.asInternal . Data.Set.fromList
    s = mkElemVar (mkElementVariable "s" setSort)

    mkInt :: InternalVariable variable => Integer -> TermLike variable
    mkInt = Int.asInternal
    intSort = Builtin.intSort
    zero, one :: InternalVariable variable => TermLike variable
    zero = mkInt 0
    one = mkInt 1
    x = mkElemVar (mkElementVariable "x" intSort)
    y = mkElemVar (mkElementVariable "y" intSort)

withInternalized
    :: (TermLike VariableName -> Assertion)
    -> TestName
    -> TermLike VariableName
    -> TestTree
withInternalized check name origin =
    testCase name (check $ Kore.internalize metadata origin)

internalizes
    :: HasCallStack
    => TestName
    -> TermLike VariableName
    -> TermLike VariableName
    -> TestTree
internalizes name origin expect =
    withInternalized (assertEqual "" expect) name origin

notInternalizes
    :: HasCallStack
    => TestName
    -> TermLike VariableName
    -> TestTree
notInternalizes name origin =
    withInternalized (assertEqual "" origin) name origin

metadata :: SmtMetadataTools Attribute.Symbol
metadata = Builtin.testMetadataTools

test_sortModuleClaims :: TestTree
test_sortModuleClaims =
    testCase "sort claims" $ do
        let verifiedModule =
                indexModule Builtin.testModuleWithTwoClaims
                & ixSetLocation 0 (from $ FileLocation "file" 5 3)
                & ixSetLocation 1 (from $ FileLocation "file" 1 1)
            withSortedClaims = sortModuleClaims verifiedModule
        assertEqual ""
            (indexedModuleClaims withSortedClaims)
            (indexedModuleClaims verifiedModule & reverse)
  where
    ixSetLocation
        :: Int
        -> SourceLocation
        -> VerifiedModule declAtts
        -> VerifiedModule declAtts
    ixSetLocation index sourceLocation verifiedModule =
        verifiedModule
        & field @"indexedModuleClaims"
            %~ (ix index . Lens._1 . field @"sourceLocation" .~ sourceLocation)
