{-# OPTIONS_GHC -Wno-name-shadowing #-}
module Test.Kore.SMT.SMT where

import Test.QuickCheck
       ( Property, (===) )

import           Data.Map
import           Data.Reflection


import           Kore.AST.PureML
import           Kore.AST.Sentence
import           Kore.AST.MetaOrObject
import           Kore.ASTUtils.SmartConstructors
import           Kore.ASTUtils.SmartPatterns
import           Kore.Proof.Dummy


import           Kore.IndexedModule.IndexedModule
import           Kore.IndexedModule.MetadataTools
import           Kore.SMT.SMT

import           Test.Kore.Builtin.Int hiding 
                 ( intModule, indexedModules )
import           Test.Kore.Builtin.Bool 
                 ( boolSort ) 

indexedModules :: Map ModuleName (KoreIndexedModule SMTAttributes)
indexedModules = verify intDefinition

intModule :: KoreIndexedModule SMTAttributes
Just intModule = Data.Map.lookup intModuleName indexedModules

tools :: MetadataTools Object SMTAttributes
tools = extractMetadataTools intModule

vInt :: String -> CommonPurePattern Object
vInt s = V $ s `varS` intSort

a, b, c :: CommonPurePattern Object
a = vInt "a"
b = vInt "b"
c = vInt "c"

vBool :: String -> CommonPurePattern Object
vBool s = V $ s `varS` boolSort

p, q :: CommonPurePattern Object
p = vBool "p"
q = vBool "q"

type Op = CommonPurePattern Object -> CommonPurePattern Object -> CommonPurePattern Object
plus, sub, mul, div :: Op
plus  a b = App_ addSymbol  [a, b]
sub a b = App_ subSymbol  [a, b]
mul a b = App_ mulSymbol  [a, b]
div   a b = App_ tdivSymbol [a, b]

prop_1 :: Property
prop_1 = run prop1

prop_2 :: Property
prop_2 = run prop2

prop_3 :: Property
prop_3 = run prop3

prop_4 :: Property
prop_4 = run prop4

prop_pierce :: Property
prop_pierce = run propPierce

prop_tdiv :: Property
prop_tdiv = run propDiv

prop_tmod :: Property
prop_tmod = run propMod

prop_demorgan :: Property
prop_demorgan = run propDeMorgan

prop_true :: Property
prop_true = run propTrue

prop_false :: Property
prop_false = run propFalse

run :: CommonPurePattern Object -> Property
run prop = (give tools $ provePattern prop) === Just True

prop1 :: CommonPurePattern Object
prop1 = dummyEnvironment $ mkNot $ 
  App_ ltSymbol [a, intLiteral 0] 
  `mkAnd` 
  App_ ltSymbol [intLiteral 0, a]

prop2 :: CommonPurePattern Object
prop2 = dummyEnvironment $ mkNot $ 
  App_ ltSymbol [a `plus` a, a `plus` b]
  `mkAnd` 
  App_ ltSymbol [b `plus` b, a `plus` b]

prop3 :: CommonPurePattern Object
prop3 = dummyEnvironment $
  App_ ltSymbol [a, b]
  `mkImplies`
  (App_ ltSymbol [b, c]
  `mkImplies`
  App_ ltSymbol [a, c])

prop4 :: CommonPurePattern Object
prop4 = dummyEnvironment $ mkNot $
  App_ eqSymbol 
  [ intLiteral 1 `plus` (intLiteral 2 `mul` a)
  , intLiteral 2 `mul` b
  ]
 
prop5 :: CommonPurePattern Object
prop5 = dummyEnvironment $  
  App_ eqSymbol
  [ intLiteral 0 `sub` (a `mul` a)
  , b `mul` b 
  ]
  `mkImplies`
  App_ eqSymbol
  [ a
  , intLiteral 0
  ]

prop6 :: CommonPurePattern Object
prop6 = dummyEnvironment $ 
  (
  App_ leSymbol [a, b]
  `mkIff`
  App_ gtSymbol [b, a]
  )
  `mkAnd`
  (
  App_ geSymbol [a, b]
  `mkIff`
  App_ ltSymbol [b, a]
  )


propDiv :: CommonPurePattern Object
propDiv = dummyEnvironment $
  App_ ltSymbol [intLiteral 0, a]
  `mkImplies`
  App_ ltSymbol [App_ tdivSymbol [a, intLiteral 2], a]

propMod :: CommonPurePattern Object
propMod = dummyEnvironment $ 
  App_ eqSymbol 
    [ App_ tmodSymbol [a `mul` intLiteral 2, intLiteral 2]
    , intLiteral 0
    ]

propPierce :: CommonPurePattern Object
propPierce = dummyEnvironment $
  ((p `mkImplies` q) `mkImplies` p) `mkImplies` p

propDeMorgan :: CommonPurePattern Object
propDeMorgan = dummyEnvironment $ 
  (mkNot $ p `mkOr` q) `mkIff` (mkNot p `mkAnd` mkNot q)

propTrue :: CommonPurePattern Object
propTrue = dummyEnvironment $ mkTop

propFalse :: CommonPurePattern Object
propFalse = dummyEnvironment $ mkIff (mkNot p) (p `mkImplies` mkBottom)


