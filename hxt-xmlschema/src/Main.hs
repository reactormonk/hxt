{-# OPTIONS_GHC -fno-warn-orphans #-}

import Text.XML.HXT.Core hiding (getChildren, getElemName, isElem, isText, getAttrName, getText)
-- TODO: ...Core ()

import Text.XML.HXT.Curl
import Text.XML.HXT.Arrow.XmlRegex

import Data.Tree.NTree.TypeDefs

import qualified Text.XML.HXT.DOM.XmlNode as XN

import Data.Map (Map, lookup, fromList, toList, keys, elems, empty, insert, union)
-- TODO import qualified Data.Map as M ... M.lookup

import Data.Maybe (fromMaybe)

import Prelude hiding (lookup)

import Data.List (partition)

import Control.Monad.Identity
import Control.Monad.Reader
import Control.Monad.Writer hiding (Any, All)
import Control.Applicative ( (<$>) )

import Text.XML.HXT.XMLSchema.W3CDataTypeCheck

instance Ord QName where -- TODO: orphan instance
  compare x y = compare (qualifiedName x) (qualifiedName y)

-- Type definitions

data XmlSchema         = XmlSchema
                       { sTargetNS        :: Maybe Namespace
                       , sIncludes        :: Includes 
                       , sSimpleTypes     :: SimpleTypeMap
                       , sComplexTypes    :: ComplexTypeMap
                       , sElements        :: ElementMap
                       , sGroups          :: GroupMap
                       , sAttributes      :: AttributeMap
                       , sAttributeGroups :: AttributeGroupMap
                       }
                       deriving (Show, Eq)

type Namespace         = String
type Includes          = [Include]
type SimpleTypeMap     = Map QName SimpleType
type ComplexTypeMap    = Map QName ComplexType
type ElementMap        = Map QName Element
type GroupMap          = Map QName Group
type AttributeMap      = Map QName Attribute
type AttributeGroupMap = Map QName AttributeGroup

data XmlSchema'        = XmlSchema'
                       { targetNS :: Maybe Namespace
                       , parts    :: [XmlSchemaPart]
                       }
data XmlSchemaPart     = In {unIn :: Include}
                       | St {unSt :: (QName, SimpleType)}
                       | Ct {unCt :: (QName, ComplexType)}
                       | El {unEl :: Element}
                       | Gr {unGr :: (QName, Group)}
                       | At {unAt :: Attribute}
                       | Ag {unAg :: (QName, AttributeGroup)}

data Include           = Incl  {unIncl  :: Location}
                       | Imp   {unImp   :: (Location, Namespace)}
                       | Redef {unRedef :: (Location, Redefinitions)}
                       deriving (Show, Eq)
type Location          = String
type Redefinitions     = [Redefinition]
data Redefinition      = RedefSt {unRedefSt :: (QName, SimpleType)}
                       | RedefCt {unRedefCt :: (QName, ComplexType)}
                       | RedefGr {unRedefGr :: (QName, Group)}
                       | RedefAg {unRedefAg :: (QName, AttributeGroup)}
                       deriving (Show, Eq)

data SimpleType        = Restr {unRestr :: STRestriction}
                       | Lst   {unLst   :: STList}
                       | Un    {unUn    :: STUnion}
                       deriving (Show, Eq)
type STRestriction     = (SimpleTypeRef, RestrAttrs)
data SimpleTypeRef     = BaseAttr        {unBaseAttr        :: QName}
                       | STRAnonymStDecl {unSTRAnonymStDecl :: SimpleType}
                       deriving (Show, Eq)
type RestrAttrs        = [RestrAttr]
data RestrAttr         = MinIncl        {unMinIncl        :: Value}
                       | MaxIncl        {unMaxIncl        :: Value}
                       | MinExcl        {unMinExcl        :: Value}
                       | MaxExcl        {unMaxExcl        :: Value}
                       | TotalDigits    {unTotalDigits    :: Value}
                       | FractionDigits {unFractionDigits :: Value}
                       | Length         {unLength         :: Value}
                       | MinLength      {unMinLength      :: Value}
                       | MaxLength      {unMaxLength      :: Value}
                       | Enumeration    {unEnumeration    :: Value}
                       | Pattern        {unPattern        :: Value}
                       | WhiteSpace     {unWhiteSpace     :: Value}
                       deriving (Show, Eq)
type Value             = String
data STList            = ItemTypeAttr    {unItemTypeAttr    :: QName}
                       | STLAnonymStDecl {unSTLAnonymStDecl :: SimpleType}
                       deriving (Show, Eq)
data STUnion           = STUnion
                       { memberTypes :: Maybe QNames
                       , anonymDecls :: [SimpleType]
                       }
                       deriving (Show, Eq)
type QNames            = [QName]

data ComplexType       = ComplexType
                       { ctMixed :: Maybe String
                       , ctDef   :: CTDef
                       }
                       deriving (Show, Eq)
data CTDef             = SCont {unSCont :: SimpleContent}
                       | CCont {unCCont :: ComplexContent}
                       | NewCT {unNewCT :: CTModel}
                       deriving (Show, Eq)

data SimpleContent     = SCExt   {unSCExt   :: SCExtension}
                       | SCRestr {unSCRestr :: SCRestriction}
                       deriving (Show, Eq)
type SCExtension       = (QName, AttrList)
type SCRestriction     = (STRestriction, AttrList)

data ComplexContent    = ComplexContent
                       { ccMixed :: Maybe String
                       , ccDef   :: CCDef
                       }
                       deriving (Show, Eq)
data CCDef             = CCExt   {unCCExt   :: CCExtension}
                       | CCRestr {unCCRestr :: CCRestriction}
                       deriving (Show, Eq)
type CCExtension       = (QName, CTModel)
type CCRestriction     = (QName, CTModel)

type CTModel           = (Maybe CTCompositor, AttrList)
data CTCompositor      = CompGr {unCompGr :: (MinMaxOcc, Group)}
                       | CompAl {unCompAl :: (MinMaxOcc, All)}
                       | CompCh {unCompCh :: (MinMaxOcc, Choice)}
                       | CompSq {unCompSq :: (MinMaxOcc, Sequence)}
                       deriving (Show, Eq)
data MinMaxOcc         = MinMaxOcc
                       { minOcc :: Maybe String
                       , maxOcc :: Maybe String
                       }
                       deriving (Show, Eq)
type All               = [(MinMaxOcc, Element)]
type Choice            = [ChSeqContent]
type Sequence          = [ChSeqContent]
data ChSeqContent      = ChSeqEl {unChSeqEl :: (MinMaxOcc, Element)}
                       | ChSeqGr {unChSeqGr :: (MinMaxOcc, Group)}
                       | ChSeqCh {unChSeqCh :: (MinMaxOcc, Choice)}
                       | ChSeqSq {unChSeqSq :: (MinMaxOcc, Sequence)}
                       | ChSeqAn {unChSeqAn :: (MinMaxOcc, Any)}
                       deriving (Show, Eq)
data Any               = Any
                       { namespace       :: Maybe Namespace
                       , processContents :: Maybe String
                       }
                       deriving (Show, Eq)
type AttrList          = [AttrListElem]
data AttrListElem      = Attr    {unAttr    :: Attribute}
                       | AttrGrp {unAttrGrp :: AttributeGroup}
                       | AnyAttr {unAnyAttr :: AnyAttribute}
                       deriving (Show, Eq)
type AnyAttribute      = Any

data Element           = ElRef {unElRef :: QName}
                       | ElDef {unElDef :: ElementDef}
                       deriving (Show, Eq)
data ElementDef        = ElementDef
                       { elemName        :: QName
                       , elemTypeDef     :: ElemTypeDef
                       }
                       deriving (Show, Eq)
data ElemTypeDef       = ETDTypeAttr     {unETDTypeAttr     :: QName}
                       | ETDAnonymStDecl {unETDAnonymStDecl :: SimpleType}
                       | ETDAnonymCtDecl {unETDAnonymCtDecl :: ComplexType}
                       deriving (Show, Eq)

data Group             = GrpRef {unGrpRef :: QName}
                       | GrpDef {unGrpDef :: Maybe GroupContDef}
                       deriving (Show, Eq)
data GroupContDef      = Al {unAl :: All}
                       | Ch {unCh :: Choice}
                       | Sq {unSq :: Sequence}
                       deriving (Show, Eq)

data Attribute         = AttrRef {unAttrRef :: QName}
                       | AttrDef {unAttrDef :: AttributeDef}
                       deriving (Show, Eq)
data AttributeDef      = AttributeDef
                       { attrName       :: QName
                       , attrTypeDef    :: AttrTypeDef
                       , attrUse        :: Maybe String
                       }
                       deriving (Show, Eq)
data AttrTypeDef       = ATDTypeAttr   {unATDTypeAttr   :: QName}
                       | ATDAnonymDecl {unATDAnonymDecl :: SimpleType}
                       deriving (Show, Eq)

data AttributeGroup    = AttrGrpRef {unAttrGrpRef :: QName}
                       | AttrGrpDef {unAttrGrpDef :: AttrList}
                       deriving (Show, Eq)

-- Namespace handling

nsUri :: String
nsUri    = "http://www.w3.org/2001/XMLSchema"

nsPrefix :: String
nsPrefix = "xs"

xpElem' :: String -> PU a -> PU a
xpElem' name
    = xpElemNS nsUri nsPrefix name

xpSchemaElem :: String -> PU a -> PU a
xpSchemaElem name
    = xpElem' name . xpFilterSchema

xpFilterSchema :: PU a -> PU a
xpFilterSchema
    = -- keep elems from xs namespace which are not blacklisted
      xpFilterCont (isXmlSchemaElem           >>> neg elementBlacklist) .
      -- keep attrs without namespace which are not blacklisted
      xpFilterAttr (isAttrWithoutNamespaceUri >>> neg attributeBlacklist)
      where
      -- element blacklist
      isXmlSchemaElem           = hasNameWith ((== nsUri) . namespaceUri)
      elementBlacklist          = foldr (<+>) none $ map hasQName $
                                  [ mkQName nsPrefix "annotation"           nsUri
                                  , mkQName nsPrefix "notation"             nsUri
                                  -- irrelevant content for element
                                  , mkQName nsPrefix "unique"               nsUri
                                  , mkQName nsPrefix "key"                  nsUri
                                  , mkQName nsPrefix "keyref"               nsUri
                                  ]
      -- attribute blacklist
      isAttrWithoutNamespaceUri = hasNameWith (null       . namespaceUri)
      attributeBlacklist        = foldr (<+>) none $ map hasQName $
                                  [ mkQName ""       "id"                   ""
                                  -- irrelevant attributes for schema
                                  , mkQName ""       "attributeFormDefault" ""
                                  , mkQName ""       "blockDefault"         ""
                                  , mkQName ""       "elementFormDefault"   ""
                                  , mkQName ""       "finalDefault"         ""
                                  , mkQName ""       "version"              ""
                                  , mkQName ""       "lang"                 ""
                                  -- irrelevant attributes for simpleType, complexType and element
                                  , mkQName ""       "final"                ""
                                  -- irrelevant attributes for simpleType restrictions, complexType, element and attribute
                                  , mkQName ""       "fixed"                ""
                                  -- irrelevant attributes for complexType and element
                                  , mkQName ""       "abstract"             ""
                                  , mkQName ""       "block"                ""
                                  -- irrelevant attributes for element and attribute
                                  , mkQName ""       "default"              ""
                                  , mkQName ""       "form"                 ""
                                  -- irrelevant attributes for element
                                  , mkQName ""       "nillable"             ""
                                  , mkQName ""       "substitutionGroup"    ""
                                  ]

-- Conversion between Schema and Schema'

toSchema :: XmlSchema' -> XmlSchema
toSchema s
  = toSchemaRec s [] empty empty empty empty empty empty
    where
    toSchemaRec (XmlSchema' tns [])                ins sts cts els grs ats ags
      = XmlSchema tns ins sts cts els grs ats ags
    toSchemaRec (XmlSchema' tns ((In incl)   :xs)) ins sts cts els grs ats ags
      = toSchemaRec (XmlSchema' tns xs) (ins ++ [incl]) sts cts els grs ats ags -- keep ordering of includes
    toSchemaRec (XmlSchema' tns ((St (k, st)):xs)) ins sts cts els grs ats ags
      = toSchemaRec (XmlSchema' tns xs) ins (insert k st sts) cts els grs ats ags
    toSchemaRec (XmlSchema' tns ((Ct (k, ct)):xs)) ins sts cts els grs ats ags
      = toSchemaRec (XmlSchema' tns xs) ins sts (insert k ct cts) els grs ats ags
    toSchemaRec (XmlSchema' tns ((El el)     :xs)) ins sts cts els grs ats ags
      = toSchemaRec (XmlSchema' tns xs) ins sts cts (insert (elemName (unElDef el)) el els) grs ats ags
    toSchemaRec (XmlSchema' tns ((Gr (k, gr)):xs)) ins sts cts els grs ats ags
      = toSchemaRec (XmlSchema' tns xs) ins sts cts els (insert k gr grs) ats ags
    toSchemaRec (XmlSchema' tns ((At at)     :xs)) ins sts cts els grs ats ags
      = toSchemaRec (XmlSchema' tns xs) ins sts cts els grs (insert (attrName (unAttrDef at)) at ats) ags
    toSchemaRec (XmlSchema' tns ((Ag (k, ag)):xs)) ins sts cts els grs ats ags
      = toSchemaRec (XmlSchema' tns xs) ins sts cts els grs ats (insert k ag ags)

-- Pickler definitions

xpQName :: PU QName
xpQName
  = xpWrap (mkName, qualifiedName) xpText -- TODO: (\ x -> mkQName nsPrefix x nsUri, qualifiedName) ?
                                          --       namespace-normalisation:
                                          --       if xs: is used by different ns: rename all xs: elements
                                          --       if alias for xs is used (e.g. ys etc.): rename to xs:

-- space-separated list of QNames
xpQNames :: PU QNames
xpQNames
  = xpWrap ( \ x -> map mkName $ words x
           , \ x -> (qualifiedName $ head x) ++ (concat $ map (\ y -> ' ':(qualifiedName y)) (tail x))
           ) xpText

xpXmlSchema' :: PU XmlSchema'
xpXmlSchema'
  = xpSchemaElem "schema" $
    -- xpAddNSDecl nsPrefix nsUri $
    xpFilterSchema $
    xpWrap (\ (a, b) -> XmlSchema' a b , \ t -> (targetNS t, parts t)) $
    xpPair (xpOption $ xpAttr "targetNamespace" xpText) $
    xpList $ xpSchemaPart

xpSchemaPart :: PU XmlSchemaPart
xpSchemaPart
  = xpAlt tag ps
    where
    tag (In _) = 0
    tag (St _) = 1
    tag (Ct _) = 2
    tag (El _) = 3
    tag (Gr _) = 4
    tag (At _) = 5
    tag (Ag _) = 6
    ps = [ xpWrap (In, unIn) $ xpInclude
         , xpWrap (St, unSt) $ xpSchemaElem "simpleType"     $ xpPair (xpAttr "name" xpQName) xpSimpleType
         , xpWrap (Ct, unCt) $ xpSchemaElem "complexType"    $ xpPair (xpAttr "name" xpQName) xpComplexType
         , xpWrap (El, unEl) $ xpSchemaElem "element"        $ xpElement
         , xpWrap (Gr, unGr) $ xpSchemaElem "group"          $ xpPair (xpAttr "name" xpQName) xpGroup
         , xpWrap (At, unAt) $ xpSchemaElem "attribute"      $ xpAttribute
         , xpWrap (Ag, unAg) $ xpSchemaElem "attributeGroup" $ xpPair (xpAttr "name" xpQName) xpAttributeGroup
         ]

xpInclude :: PU Include
xpInclude
  = xpAlt tag ps
    where
    tag (Incl _)  = 0
    tag (Imp _)   = 1
    tag (Redef _) = 2
    ps = [ xpWrap (Incl,  unIncl)  $ xpSchemaElem "include"  $ xpAttr "schemaLocation" xpText
         , xpWrap (Imp,   unImp)   $ xpSchemaElem "import"   $ xpPair (xpAttr "schemaLocation" xpText) (xpAttr "namespace" xpText)
         , xpWrap (Redef, unRedef) $ xpSchemaElem "redefine" $ xpPair (xpAttr "schemaLocation" xpText) (xpList xpRedefinition)
         ]

xpRedefinition :: PU Redefinition
xpRedefinition
  = xpAlt tag ps
    where
    tag (RedefSt _) = 0
    tag (RedefCt _) = 1
    tag (RedefGr _) = 2
    tag (RedefAg _) = 3
    ps = [ xpWrap (RedefSt, unRedefSt) $ xpSchemaElem "simpleType"     $ xpPair (xpAttr "name" xpQName) xpSimpleType
         , xpWrap (RedefCt, unRedefCt) $ xpSchemaElem "complexType"    $ xpPair (xpAttr "name" xpQName) xpComplexType
         , xpWrap (RedefGr, unRedefGr) $ xpSchemaElem "group"          $ xpPair (xpAttr "name" xpQName) xpGroup
         , xpWrap (RedefAg, unRedefAg) $ xpSchemaElem "attributeGroup" $ xpPair (xpAttr "name" xpQName) xpAttributeGroup
         ]

xpSimpleType :: PU SimpleType
xpSimpleType
  = xpAlt tag ps
    where
    tag (Restr _) = 0
    tag (Lst _)   = 1
    tag (Un _)    = 2
    ps = [ xpWrap (Restr, unRestr) $ xpSchemaElem "restriction" $ xpSTRestriction
         , xpWrap (Lst,   unLst)   $ xpSchemaElem "list"        $ xpSTList
         , xpWrap (Un,    unUn)    $ xpSchemaElem "union"       $ xpSTUnion
         ]

xpSTRestriction :: PU STRestriction
xpSTRestriction
  = xpPair xpSimpleTypeRef $ xpList $ xpRestrAttr

xpSimpleTypeRef :: PU SimpleTypeRef
xpSimpleTypeRef
  = xpAlt tag ps
    where
    tag (BaseAttr _)        = 0
    tag (STRAnonymStDecl _) = 1
    ps = [ xpWrap (BaseAttr,        unBaseAttr)        $ xpAttr "base" xpQName
         , xpWrap (STRAnonymStDecl, unSTRAnonymStDecl) $ xpSchemaElem "simpleType" $ xpSimpleType
         ]

xpRestrAttr :: PU RestrAttr
xpRestrAttr
  = xpAlt tag ps
    where
    tag (MinIncl _)        = 0
    tag (MaxIncl _)        = 1
    tag (MinExcl _)        = 2
    tag (MaxExcl _)        = 3
    tag (TotalDigits _)    = 4
    tag (FractionDigits _) = 5
    tag (Length _)         = 6
    tag (MinLength _)      = 7
    tag (MaxLength _)      = 8
    tag (Enumeration _)    = 9
    tag (Pattern _)        = 10
    tag (WhiteSpace _)     = 11
    ps = [ xpWrap (MinIncl,        unMinIncl)        $ xpSchemaElem "minInclusive"   $ xpAttr "value" xpText
         , xpWrap (MaxIncl,        unMaxIncl)        $ xpSchemaElem "maxInclusive"   $ xpAttr "value" xpText
         , xpWrap (MinExcl,        unMinExcl)        $ xpSchemaElem "minExclusive"   $ xpAttr "value" xpText
         , xpWrap (MaxExcl,        unMaxExcl)        $ xpSchemaElem "maxExclusive"   $ xpAttr "value" xpText
         , xpWrap (TotalDigits,    unTotalDigits)    $ xpSchemaElem "totalDigits"    $ xpAttr "value" xpText
         , xpWrap (FractionDigits, unFractionDigits) $ xpSchemaElem "fractionDigits" $ xpAttr "value" xpText
         , xpWrap (Length,         unLength)         $ xpSchemaElem "length"         $ xpAttr "value" xpText
         , xpWrap (MinLength,      unMinLength)      $ xpSchemaElem "minLength"      $ xpAttr "value" xpText
         , xpWrap (MaxLength,      unMaxLength)      $ xpSchemaElem "maxLength"      $ xpAttr "value" xpText
         , xpWrap (Enumeration,    unEnumeration)    $ xpSchemaElem "enumeration"    $ xpAttr "value" xpText
         , xpWrap (Pattern,        unPattern)        $ xpSchemaElem "pattern"        $ xpAttr "value" xpText
         , xpWrap (WhiteSpace,     unWhiteSpace)     $ xpSchemaElem "whiteSpace"     $ xpAttr "value" xpText
         ]

xpSTList :: PU STList
xpSTList
  = xpAlt tag ps
    where
    tag (ItemTypeAttr _)    = 0
    tag (STLAnonymStDecl _) = 1
    ps = [ xpWrap (ItemTypeAttr,    unItemTypeAttr)    $ xpAttr "itemType" xpQName
         , xpWrap (STLAnonymStDecl, unSTLAnonymStDecl) $ xpSchemaElem "simpleType" $ xpSimpleType
         ]

xpSTUnion :: PU STUnion
xpSTUnion
  = xpWrap (\ (a, b) -> STUnion a b , \ t -> (memberTypes t, anonymDecls t)) $
    xpPair (xpOption $ xpAttr "memberTypes" xpQNames) $
    xpList $ xpSchemaElem "simpleType" $ xpSimpleType

xpComplexType :: PU ComplexType
xpComplexType
  = xpWrap (\ (a, b) -> ComplexType a b , \ t -> (ctMixed t, ctDef t)) $
    xpPair (xpOption $ xpAttr "mixed" xpText) xpCTDef

xpCTDef :: PU CTDef
xpCTDef
  = xpAlt tag ps
    where
    tag (SCont _) = 0
    tag (CCont _) = 1
    tag (NewCT _) = 2
    ps = [ xpWrap (SCont, unSCont) $ xpSchemaElem "simpleContent"  $ xpSimpleContent
         , xpWrap (CCont, unCCont) $ xpSchemaElem "complexContent" $ xpComplexContent
         , xpWrap (NewCT, unNewCT) $ xpCTModel
         ]

xpSimpleContent :: PU SimpleContent
xpSimpleContent
  = xpAlt tag ps
    where
    tag (SCExt _)   = 0
    tag (SCRestr _) = 1
    ps = [ xpWrap (SCExt,   unSCExt)   $ xpSchemaElem "extension"   $ xpPair (xpAttr "base" xpQName) xpAttrList
         , xpWrap (SCRestr, unSCRestr) $ xpSchemaElem "restriction" $ xpPair xpSTRestriction xpAttrList 
         ]

xpComplexContent :: PU ComplexContent
xpComplexContent
  = xpWrap (\ (a, b) -> ComplexContent a b , \ t -> (ccMixed t, ccDef t)) $
    xpPair (xpOption $ xpAttr "mixed" xpText) xpCCDef

xpCCDef :: PU CCDef
xpCCDef
  = xpAlt tag ps
    where
    tag (CCExt _)   = 0
    tag (CCRestr _) = 1
    ps = [ xpWrap (CCExt,   unCCExt)   $ xpSchemaElem "extension"   $ xpPair (xpAttr "base" xpQName) $ xpCTModel
         , xpWrap (CCRestr, unCCRestr) $ xpSchemaElem "restriction" $ xpPair (xpAttr "base" xpQName) $ xpCTModel
         ]

xpCTModel :: PU CTModel
xpCTModel
  = xpPair (xpOption xpCTCompositor) xpAttrList

xpCTCompositor :: PU CTCompositor
xpCTCompositor
  = xpAlt tag ps
    where
    tag (CompGr _) = 0
    tag (CompAl _) = 1
    tag (CompCh _) = 2
    tag (CompSq _) = 3
    ps = [ xpWrap (CompGr, unCompGr) $ xpSchemaElem "group"    $ xpPair xpMinMaxOcc xpGroup
         , xpWrap (CompAl, unCompAl) $ xpSchemaElem "all"      $ xpPair xpMinMaxOcc xpAll
         , xpWrap (CompCh, unCompCh) $ xpSchemaElem "choice"   $ xpPair xpMinMaxOcc xpSchemaChoice
         , xpWrap (CompSq, unCompSq) $ xpSchemaElem "sequence" $ xpPair xpMinMaxOcc xpSequence
         ]

xpMinMaxOcc :: PU MinMaxOcc
xpMinMaxOcc
  = xpWrap (\ (a, b) -> MinMaxOcc a b , \ t -> (minOcc t, maxOcc t)) $
    xpPair (xpOption $ xpAttr "minOccurs" xpText) (xpOption $ xpAttr "maxOccurs" xpText)

xpAll :: PU All
xpAll
  = xpList $ xpSchemaElem "element" $ xpPair xpMinMaxOcc xpElement

xpSchemaChoice :: PU Choice
xpSchemaChoice
  = xpList xpChSeqContent

xpSequence :: PU Sequence
xpSequence
  = xpList xpChSeqContent

xpChSeqContent :: PU ChSeqContent
xpChSeqContent
  = xpAlt tag ps
    where
    tag (ChSeqEl _) = 0
    tag (ChSeqGr _) = 1
    tag (ChSeqCh _) = 2
    tag (ChSeqSq _) = 3
    tag (ChSeqAn _) = 4
    ps = [ xpWrap (ChSeqEl, unChSeqEl) $ xpSchemaElem "element"  $ xpPair xpMinMaxOcc xpElement
         , xpWrap (ChSeqGr, unChSeqGr) $ xpSchemaElem "group"    $ xpPair xpMinMaxOcc xpGroup
         , xpWrap (ChSeqCh, unChSeqCh) $ xpSchemaElem "choice"   $ xpPair xpMinMaxOcc xpSchemaChoice
         , xpWrap (ChSeqSq, unChSeqSq) $ xpSchemaElem "sequence" $ xpPair xpMinMaxOcc xpSequence
         , xpWrap (ChSeqAn, unChSeqAn) $ xpSchemaElem "any"      $ xpPair xpMinMaxOcc xpAny
         ]

xpAny :: PU Any
xpAny
  = xpWrap (\ (a, b) -> Any a b , \ t -> (namespace t, processContents t)) $
    xpPair (xpOption $ xpAttr "namespace" xpText) (xpOption $ xpAttr "processContents" xpText)

xpAttrList :: PU AttrList
xpAttrList
  = xpList $
    xpAlt tag ps
    where
    tag (Attr _)    = 0
    tag (AttrGrp _) = 1
    tag (AnyAttr _) = 2
    ps = [ xpWrap (Attr,    unAttr)    $ xpSchemaElem "attribute"      $ xpAttribute
         , xpWrap (AttrGrp, unAttrGrp) $ xpSchemaElem "attributeGroup" $ xpAttributeGroup
         , xpWrap (AnyAttr, unAnyAttr) $ xpSchemaElem "anyAttribute"   $ xpAny
         ]

xpElement :: PU Element
xpElement
  = xpAlt tag ps
    where
    tag (ElRef _) = 0
    tag (ElDef _) = 1
    ps = [ xpWrap (ElRef, unElRef) $ xpAttr "ref" xpQName
         , xpWrap (ElDef, unElDef) $ xpElementDef
         ]

xpElementDef :: PU ElementDef
xpElementDef
  = xpWrap (\ (a, b) -> ElementDef a b, \ t -> (elemName t, elemTypeDef t)) $
    xpPair (xpAttr "name" xpQName) xpElemTypeDef

xpElemTypeDef :: PU ElemTypeDef
xpElemTypeDef
  = xpAlt tag ps
    where
    tag (ETDTypeAttr _)     = 0
    tag (ETDAnonymStDecl _) = 1
    tag (ETDAnonymCtDecl _) = 2
    ps = [ xpWrap (ETDTypeAttr,     unETDTypeAttr)     $ xpAttr "type" xpQName
         , xpWrap (ETDAnonymStDecl, unETDAnonymStDecl) $ xpSchemaElem "simpleType"  $ xpSimpleType
         , xpWrap (ETDAnonymCtDecl, unETDAnonymCtDecl) $ xpSchemaElem "complexType" $ xpComplexType
         ]

xpGroup :: PU Group
xpGroup
  = xpAlt tag ps
    where
    tag (GrpRef _) = 0
    tag (GrpDef _) = 1
    ps = [ xpWrap (GrpRef, unGrpRef) $ xpAttr "ref" xpQName
         , xpWrap (GrpDef, unGrpDef) $ xpOption $ xpGroupContDef
         ]

xpGroupContDef :: PU GroupContDef
xpGroupContDef
  = xpAlt tag ps
    where
    tag (Al _) = 0
    tag (Ch _) = 1
    tag (Sq _) = 2
    ps = [ xpWrap (Al, unAl) $ xpSchemaElem "all"      $ xpAll
         , xpWrap (Ch, unCh) $ xpSchemaElem "choice"   $ xpSchemaChoice
         , xpWrap (Sq, unSq) $ xpSchemaElem "sequence" $ xpSequence
         ]

xpAttribute :: PU Attribute
xpAttribute
  = xpAlt tag ps
    where
    tag (AttrRef _) = 0
    tag (AttrDef _) = 1
    ps = [ xpWrap (AttrRef, unAttrRef) $ xpAttr "ref" xpQName
         , xpWrap (AttrDef, unAttrDef) $ xpAttributeDef
         ]

xpAttributeDef :: PU AttributeDef
xpAttributeDef
  = xpWrap (\ (a, b, c) -> AttributeDef a b c, \ t -> (attrName t, attrTypeDef t, attrUse t)) $
    xpTriple (xpAttr "name" xpQName) xpAttrTypeDef (xpOption $ xpAttr "use" xpText)

xpAttrTypeDef :: PU AttrTypeDef
xpAttrTypeDef
  = xpAlt tag ps
    where
    tag (ATDTypeAttr _)   = 0
    tag (ATDAnonymDecl _) = 1
    ps = [ xpWrap (ATDTypeAttr,   unATDTypeAttr)   $ xpAttr "type" xpQName
         , xpWrap (ATDAnonymDecl, unATDAnonymDecl) $ xpSchemaElem "simpleType" $ xpSimpleType
         ]

xpAttributeGroup :: PU AttributeGroup
xpAttributeGroup
  = xpAlt tag ps
    where
    tag (AttrGrpRef _) = 0
    tag (AttrGrpDef _) = 1
    ps = [ xpWrap (AttrGrpRef, unAttrGrpRef) $ xpAttr "ref" xpQName
         , xpWrap (AttrGrpDef, unAttrGrpDef) $ xpAttrList
         ]

-- Processing of includes

resolveIncls :: XmlSchema -> Includes -> IO XmlSchema
resolveIncls s []
  = return s
resolveIncls s (x:xs)
  = do
    incl' <- resolveIncl x
    case incl' of
      Nothing   -> resolveIncls s xs
      Just incl -> resolveIncls (mergeSchemata s incl) xs

resolveIncl :: Include -> IO (Maybe XmlSchema) -- TODO: apply namespaces?
resolveIncl (Incl loc)
  = loadXmlSchema loc
resolveIncl (Imp (loc, _))       
  = loadXmlSchema loc
resolveIncl (Redef (loc, redefs))
  = do
    s' <- loadXmlSchema loc
    case s' of
      Nothing -> return Nothing
      Just s  -> return $ Just $ applyRedefs s redefs

applyRedefs :: XmlSchema -> Redefinitions -> XmlSchema
applyRedefs s []
  = s
applyRedefs (XmlSchema tns ins sts cts els grs ats ags) ((RedefSt (k, st)):xs)
  = applyRedefs (XmlSchema tns ins (insert k st sts) cts els grs ats ags) xs -- TODO: Apply redefinition to existing ST
applyRedefs (XmlSchema tns ins sts cts els grs ats ags) ((RedefCt (k, ct)):xs)
  = applyRedefs (XmlSchema tns ins sts (insert k ct cts) els grs ats ags) xs -- TODO: Apply redefinition to existing CT
applyRedefs (XmlSchema tns ins sts cts els grs ats ags) ((RedefGr (k, gr)):xs)
  = applyRedefs (XmlSchema tns ins sts cts els (insert k gr grs) ats ags) xs
applyRedefs (XmlSchema tns ins sts cts els grs ats ags) ((RedefAg (k, ag)):xs)
  = applyRedefs (XmlSchema tns ins sts cts els grs ats (insert k ag ags)) xs

mergeSchemata :: XmlSchema -> XmlSchema -> XmlSchema
mergeSchemata (XmlSchema tns _ sts cts els grs ats ags) (XmlSchema _ _ sts' cts' els' grs' ats' ags')
  = XmlSchema tns [] (union sts sts') (union cts cts') (union els els') (union grs grs') (union ats ats') (union ags ags')

-- Load schema from given url

loadXmlSchema :: String -> IO (Maybe XmlSchema)
loadXmlSchema uri
  = do
    s' <- runX ( 
                -- TODO: readDocument, add namespaces to each node, finally unpickle
                xunpickleDocument xpXmlSchema'
                                  [ withValidate yes        -- validate source
                                  , withTrace 0             -- trace processing steps?
                                  , withRemoveWS yes        -- remove redundant whitespace
                                  , withPreserveComment no  -- keep comments
                                  , withCheckNamespaces yes -- check namespaces
                                  , withCurl []             -- use libCurl for http access
                                  ] uri
               )
    if null s'
      then return Nothing
      else do
           let s = toSchema $ head s' 
           Just <$> resolveIncls s (sIncludes s)

--------------------------------------------------------------------------------------

-- XML Processing with HXT

getElemName :: XmlTree -> QName
getElemName t = fromMaybe (mkName "") $ XN.getElemName t

mkElemRE :: QName -> XmlRegex
mkElemRE s = mkPrim $ (== s) . getElemName

getElemAttrs :: XmlTree -> [(QName, String)]
getElemAttrs t = map (\ x -> (getAttrName x, getAttrValue' x)) $ fromMaybe [] $ XN.getAttrl t

getChildren :: XmlTree -> XmlTrees
getChildren (NTree _ c) = c

getElemChildren :: XmlTree -> XmlTrees
getElemChildren t = filter isRelevant $ getChildren t

isElem :: XmlTree -> Bool
isElem = XN.isElem

mkTextRE :: XmlRegex
mkTextRE = mkPrim $ isText

isText :: XmlTree -> Bool
isText = XN.isText

isRelevant :: XmlTree -> Bool
isRelevant t = (isElem t) || (isText t)

getAttrName :: XmlTree -> QName
getAttrName t = fromMaybe (mkName "") $  XN.getAttrName t

getAttrValue' :: XmlTree -> String -- TODO: List of strings instead to validate each one?
getAttrValue' t = getCombinedText $ getChildren t

getCombinedText :: XmlTrees -> String
getCombinedText t = concat $ getTexts t

getTexts :: XmlTrees -> [String]
getTexts = map getText

getText :: XmlTree -> String
getText t = fromMaybe "" $ XN.getText t

-- Read xml document

readDoc :: String -> IO (Maybe XmlTree)
readDoc uri
  = do
    s <- runX ( readDocument [ withValidate yes        -- validate source
                             , withTrace 0             -- trace processing steps?
                             , withPreserveComment no  -- remove comments
                             , withCheckNamespaces yes -- check namespaces
                             , withCurl []             -- use libCurl for http access
                             ] uri
                >>>
                ((getAttrValue "status") &&& (setAttrl none))
              )
    if (fst $ head s) == ""
      then return $ Just (snd $ head s)
      else return Nothing

--------------------------------------------------------------------------------------

-- Types for XmlSchema transformation

data ElemDesc    = ElemDesc
                 { errmsg       :: Maybe String 
                 , attrMap      :: AttrMap
                 , contentModel :: XmlRegex
                 , subElemDesc  :: SubElemDesc
                 , sttf         :: STTF
                 }

type AttrMap     = Map QName AttrMapVal
type AttrMapVal  = (Bool, STTF)
type SubElemDesc = Map QName ElemDesc
type STTF        = String -> SVal Bool

type XSC a       = ReaderT XmlSchema Identity a

runXSC :: XmlSchema -> XSC a -> a
runXSC schema xsc = runIdentity $ runReaderT xsc schema

box :: a -> [a]
box x = [x]

-- Create SimpleType test functions

knownW3CTypes :: Map QName STTF
knownW3CTypes
  = fromList
    [ (mkName "xs:string",             mkW3CCheckSTTF xsd_string)
    , (mkName "xs:normalizedString",   mkW3CCheckSTTF xsd_normalizedString)
    , (mkName "xs:token",              mkW3CCheckSTTF xsd_token)
    , (mkName "xs:language",           mkW3CCheckSTTF xsd_language)
    , (mkName "xs:NMTOKEN",            mkW3CCheckSTTF xsd_NMTOKEN)
    , (mkName "xs:NMTOKENS",           mkW3CCheckSTTF xsd_NMTOKENS)
    , (mkName "xs:Name",               mkW3CCheckSTTF xsd_Name)
    , (mkName "xs:NCName",             mkW3CCheckSTTF xsd_NCName)
    , (mkName "xs:ID",                 mkW3CCheckSTTF xsd_ID)
    , (mkName "xs:IDREF",              mkW3CCheckSTTF xsd_IDREF)
    , (mkName "xs:IDREFS",             mkW3CCheckSTTF xsd_IDREFS)
    , (mkName "xs:ENTITY",             mkW3CCheckSTTF xsd_ENTITY)
    , (mkName "xs:ENTITIES",           mkW3CCheckSTTF xsd_ENTITIES)
    , (mkName "xs:anyURI",             mkW3CCheckSTTF xsd_anyURI)
    , (mkName "xs:QName",              mkW3CCheckSTTF xsd_QName)
    , (mkName "xs:NOTATION",           mkW3CCheckSTTF xsd_NOTATION)
    , (mkName "xs:hexBinary",          mkW3CCheckSTTF xsd_hexBinary)
    , (mkName "xs:base64Binary",       mkW3CCheckSTTF xsd_base64Binary)
    , (mkName "xs:decimal",            mkW3CCheckSTTF xsd_decimal)
    , (mkName "xs:integer",            mkW3CCheckSTTF xsd_integer)
    , (mkName "xs:nonPositiveInteger", mkW3CCheckSTTF xsd_nonPositiveInteger)
    , (mkName "xs:negativeInteger",    mkW3CCheckSTTF xsd_negativeInteger)
    , (mkName "xs:nonNegativeInteger", mkW3CCheckSTTF xsd_nonNegativeInteger)
    , (mkName "xs:positiveInteger",    mkW3CCheckSTTF xsd_positiveInteger)
    , (mkName "xs:long",               mkW3CCheckSTTF xsd_long)
    , (mkName "xs:int",                mkW3CCheckSTTF xsd_int)
    , (mkName "xs:short",              mkW3CCheckSTTF xsd_short)
    , (mkName "xs:byte",               mkW3CCheckSTTF xsd_byte)
    , (mkName "xs:unsignedLong",       mkW3CCheckSTTF xsd_unsignedLong)
    , (mkName "xs:unsignedInt",        mkW3CCheckSTTF xsd_unsignedInt)
    , (mkName "xs:unsignedShort",      mkW3CCheckSTTF xsd_unsignedShort)
    , (mkName "xs:unsignedByte",       mkW3CCheckSTTF xsd_unsignedByte)
    -- TODO: not implemented yet in DataTypeLibW3C / W3CDataTypeCheck
    , (mkName "xs:boolean",            mkWarnSTTF "no check for boolean implemented.")
    , (mkName "xs:float",              mkWarnSTTF "no check for float implemented.")
    , (mkName "xs:double",             mkWarnSTTF "no check for double implemented.")
    , (mkName "xs:time",               mkWarnSTTF "no check for time implemented.")
    , (mkName "xs:duration",           mkWarnSTTF "no check for duration implemented.")
    , (mkName "xs:date",               mkWarnSTTF "no check for date implemented.")
    , (mkName "xs:dateTime",           mkWarnSTTF "no check for dateTime implemented.")
    , (mkName "xs:gDay",               mkWarnSTTF "no check for gDay implemented.")
    , (mkName "xs:gMonth",             mkWarnSTTF "no check for gMonth implemented.")
    , (mkName "xs:gMonthDay",          mkWarnSTTF "no check for gMonthDay implemented.")
    , (mkName "xs:gYear",              mkWarnSTTF "no check for gYear implemented.")
    , (mkName "xs:gYearMonth",         mkWarnSTTF "no check for gYearMonth implemented.")
    ]

checkBothSTTF :: STTF -> STTF -> STTF
checkBothSTTF tf1 tf2
  = \ x -> do
           tf1res <- tf1 x
           tf2res <- tf2 x
           return (tf1res && tf2res)

mkNoTextSTTF :: STTF
mkNoTextSTTF
  = \ s -> do
           env <- ask
           if not $ null $ unwords $ words s
             then do
                  tell [(xpath env, "no text allowed here.")]
                  return False
             else return True

mkPassThroughSTTF :: STTF
mkPassThroughSTTF
  = \ _ -> return True

mkWarnSTTF :: String -> STTF
mkWarnSTTF s
  = \ _ -> do
           env <- ask
           tell [(xpath env, s)]
           return True

mkErrorSTTF :: String -> STTF
mkErrorSTTF s
  = \ _ -> do
           env <- ask
           tell [(xpath env, s)]
           return False

mkW3CCheckSTTF :: DatatypeName -> STTF
mkW3CCheckSTTF d
  = do
    \ s -> case datatypeAllowsW3C d [] s of
             Nothing  -> return True
             Just msg -> do
                         env <- ask
                         tell [(xpath env, msg)]
                         return False

lookupSTTF :: QName -> XSC STTF -- TODO: pass list of restrictions
lookupSTTF n
  = do
    s <- ask
    case lookup n knownW3CTypes of
      Just tf -> return tf
      Nothing -> case lookup n (sSimpleTypes s) of
                   Nothing -> return $ mkErrorSTTF "type validation error: illegal type reference in schema file"
                   Just t  -> stToSTTF t

rlistToSTTF :: RestrAttrs -> STTF
rlistToSTTF _
  = mkPassThroughSTTF -- TODO: implement restriction checks
-- MinIncl
-- MaxIncl
-- MinExcl
-- MaxExcl
-- TotalDigits
-- FractionDigits
-- Length (siehe LibUtils)
-- MinLength (siehe LibUtils)
-- MaxLength (siehe LibUtils)
-- Enumeration -- not implemented yet
-- Pattern
-- WhiteSpace -- values anpassen auf whitespace-festlegung (vor / nach pattern?)

rstrToSTTF :: STRestriction -> XSC STTF -- TODO: pass restriction list to lookupSTTF
rstrToSTTF (tref, rlist)
  = do
    baseTF  <- case tref of
                 BaseAttr n        -> lookupSTTF n
                 STRAnonymStDecl t -> stToSTTF t
    return $ checkBothSTTF baseTF $ rlistToSTTF rlist

stToSTTF :: SimpleType -> XSC STTF
stToSTTF (Restr rstr)
  = rstrToSTTF rstr -- TODO: pass restriction list to basic type check
stToSTTF (Lst tref)
  = do
    baseTF  <- case tref of
                 ItemTypeAttr n    -> lookupSTTF n
                 STLAnonymStDecl t -> stToSTTF t
    return $ \ x -> do
                    env <- ask
                    if not $ foldr (&&) True $ fst $ runSVal env $ mapM baseTF $ words x
                      then do
                           tell [(xpath env, "value does not match list type")]
                           return False
                      else return True
stToSTTF (Un ts)
  = do
    trefTFs <- case memberTypes ts of
                 Nothing    -> return []
                 Just trefs -> mapM lookupSTTF trefs
    tdefTFs <- mapM stToSTTF $ anonymDecls ts
    return $ \ x -> do
                    env <- ask
                    if not $ foldr (||) False $ fst $ runSVal env $ mapM (\ f -> f x) (trefTFs ++ tdefTFs)
                      then do
                           tell [(xpath env, "value does not match union type")]
                           return False
                      else return True

-- Create AttrMap entries

createAttrMapEntry :: Attribute -> XSC (QName, AttrMapVal)
createAttrMapEntry (AttrRef n)
  = do
    s <- ask
    case lookup n (sAttributes s) of
           Just a  -> createAttrMapEntry a
           Nothing -> do
                      let errorSTTF = mkErrorSTTF "attribute validation error: illegal attribute reference in schema file"
                      return (n, (False, errorSTTF))
createAttrMapEntry (AttrDef (AttributeDef n tdef use))
  = do
    let req = case use of
                Nothing -> False
                Just s  -> case s of
                             "required" -> True
                             _          -> False
    tf <- case tdef of
            ATDTypeAttr r   -> lookupSTTF r
            ATDAnonymDecl t -> stToSTTF t    
    return (n, (req, tf))

-- Create Element Description for Validation

attrGrpToAttrList :: AttributeGroup -> XSC AttrList
attrGrpToAttrList g
  = do
    s <- ask
    case g of
      AttrGrpRef n -> case lookup n $ sAttributeGroups s of
                        Nothing -> return []
                        Just g' -> attrGrpToAttrList g'
      AttrGrpDef l -> return l

attrListToAttrMap :: AttrList -> XSC AttrMap
attrListToAttrMap l
  = fromList <$> attrListToAttrMap' l

attrListToAttrMap' :: AttrList -> XSC [(QName, AttrMapVal)]
attrListToAttrMap' l
  = concat <$> mapM (\ x -> case x of
                              Attr    a -> box <$> createAttrMapEntry a
                              AttrGrp g -> attrGrpToAttrList g >>= attrListToAttrMap'
                              AnyAttr _ -> return [] -- TODO: AnyAttribute :: Any -- extend: AttrMap, NamespaceMap
                    ) l

mkErrorElemDesc :: String -> ElemDesc
mkErrorElemDesc s
  = ElemDesc (Just s) empty mkUnit empty mkPassThroughSTTF

mkSimpleElemDesc :: AttrMap -> STTF -> ElemDesc
mkSimpleElemDesc am tf
  = ElemDesc Nothing am mkTextRE empty tf

mkElemDesc :: AttrMap -> XmlRegex -> SubElemDesc -> STTF -> ElemDesc
mkElemDesc am cm se tf
  = ElemDesc Nothing am cm se tf

groupToElemDesc :: Group -> XSC ElemDesc
groupToElemDesc (GrpRef r)
  = do
    s <- ask
    case lookup r $ sGroups s of
      Nothing -> return $ mkErrorElemDesc "element validation error: illegal group reference in schema file"
      Just g  -> groupToElemDesc g
groupToElemDesc (GrpDef d)
  = case d of
      Nothing      -> return $ mkElemDesc empty mkUnit empty mkNoTextSTTF -- TODO: RE for empty elem (mkUnit)
      Just (Al al) -> allToElemDesc al
      Just (Ch ch) -> choiceToElemDesc ch
      Just (Sq sq) -> sequenceToElemDesc sq

elementToName :: Element -> QName
elementToName e
  = case e of
      ElRef r -> r
      ElDef d -> elemName d

allToElemDesc :: All -> XSC ElemDesc
allToElemDesc l
  = do
    eds <- mapM (\ (occ, el) -> do
                                ed <- createElemDesc el
                                return $ ( elementToName el
                                         , mkElemDesc (attrMap ed)
                                                      (mkMinMaxRE occ (contentModel ed))
                                                      (subElemDesc ed)
                                                      (sttf ed)
                                         )
                ) l
    let re = mkPerms $ map (\ (_, ed) -> contentModel ed) eds
    return $ mkElemDesc empty re (fromList eds) mkNoTextSTTF -- TODO: merge AttrMap etc.?

mkPair :: a -> b -> (a, b)
mkPair x y = (x, y)

chSeqContToElemDesc :: ChSeqContent -> XSC ElemDesc
chSeqContToElemDesc c
  = do
    (occ, ed) <- case c of
                   ChSeqEl (occ, el) -> mkPair occ <$> createElemDesc el
                   ChSeqGr (occ, gr) -> mkPair occ <$> groupToElemDesc gr
                   ChSeqCh (occ, ch) -> mkPair occ <$> choiceToElemDesc ch
                   ChSeqSq (occ, sq) -> mkPair occ <$> sequenceToElemDesc sq
                   ChSeqAn (occ, _)  -> return $ mkPair occ $ mkErrorElemDesc "not implemented yet." -- TODO: impl any :: Any
    return $ mkElemDesc (attrMap ed) (mkMinMaxRE occ (contentModel ed)) (subElemDesc ed) (sttf ed)

-- =========================================

-- TODO: refactor subElem detection

choiceToElemDesc :: Choice -> XSC ElemDesc
choiceToElemDesc l
  = do
    let names = map ( \ x -> case x of
                               ChSeqEl (_, el) -> elementToName el
                               _               -> mkName ""
                    ) l -- TODO: sense?
    eds <- zip names <$> mapM chSeqContToElemDesc l -- TODO: combine attrMaps etc.
    let se = fromList $ filter (\ (s, _) -> not $ null $ qualifiedName s) $ eds
    let re = mkAlts $ map (\ (_, ed) -> contentModel ed) eds
    return $ mkElemDesc empty re se mkNoTextSTTF

sequenceToElemDesc :: Sequence -> XSC ElemDesc
sequenceToElemDesc l
  = do
    let names = map ( \ x -> case x of
                               ChSeqEl (_, el) -> elementToName el
                               _               -> mkName ""
                    ) l -- TODO: sense?
    eds <- zip names <$> mapM chSeqContToElemDesc l -- TODO: combine attrMaps etc.
    let se = fromList $ filter (\ (s, _) -> not $ null $ qualifiedName s) $ eds
    let re = mkSeqs $ map (\ (_, ed) -> contentModel ed) eds
    return $ mkElemDesc empty re se mkNoTextSTTF

-- =========================================

readMaybeInt :: String -> Maybe Int
readMaybeInt str
  = val $ reads str
    where
    val [(x, "")] = Just x
    val _         = Nothing

mkMinMaxRE :: MinMaxOcc -> XmlRegex -> XmlRegex
mkMinMaxRE occ re
  = case readMaybeInt minOcc' of
      Nothing       -> mkZero $ "element validation error: illegal minOccurs in schema file"
      Just minOcc'' -> if maxOcc' == "unbounded"
                         then mkRep minOcc'' re
                         else case readMaybeInt maxOcc' of
                                Nothing       -> mkZero $ "element validation error: illegal maxOccurs in schema file"
                                Just maxOcc'' -> mkRng minOcc'' maxOcc'' re
    where
    minOcc' = case minOcc occ of
                Nothing -> "1"
                Just i  -> i
    maxOcc' = case maxOcc occ of
                Nothing -> "1"
                Just i  -> i

compToElemDesc :: CTCompositor -> XSC ElemDesc
compToElemDesc c
  = do
    (occ, ed) <- case c of
                   CompGr (occ, gr) -> mkPair occ <$> groupToElemDesc gr
                   CompAl (occ, al) -> mkPair occ <$> allToElemDesc al
                   CompCh (occ, ch) -> mkPair occ <$> choiceToElemDesc ch
                   CompSq (occ, sq) -> mkPair occ <$> sequenceToElemDesc sq
    return $ mkElemDesc (attrMap ed) (mkMinMaxRE occ (contentModel ed)) (subElemDesc ed) (sttf ed)

ctModelToElemDesc :: CTModel -> XSC ElemDesc
ctModelToElemDesc (comp, attrs)
  = do
    am <- attrListToAttrMap attrs
    case comp of
      Nothing -> return $ mkElemDesc am mkUnit empty mkNoTextSTTF -- TODO: RE for empty elem mkUnit (epsilon)
      Just c  -> do
                 ed <- compToElemDesc c
                 return $ mkElemDesc (union am (attrMap ed)) (contentModel ed) (subElemDesc ed) (sttf ed)

ctToElemDesc :: ComplexType -> XSC ElemDesc -- TODO: refactor to 3 functions
ctToElemDesc ct
  = do
    s <- ask
    case ctDef ct of -- TODO: ctMixed ct (Maybe String)
      SCont (SCExt   (n,             attrs)) ->
        do
        am <- attrListToAttrMap attrs
        case lookup n $ sComplexTypes s of
          Nothing  -> mkSimpleElemDesc am <$> lookupSTTF n
          Just ct' -> do
                      ed <- ctToElemDesc ct'
                      return $ mkSimpleElemDesc (union am $ attrMap ed) (sttf ed)
      SCont (SCRestr (rstr@(tref, rlist), attrs)) ->
        do
        am <- attrListToAttrMap attrs
        case tref of
          BaseAttr n        -> case lookup n $ sComplexTypes s of
                                 Nothing  -> mkSimpleElemDesc am <$> rstrToSTTF rstr
                                 Just ct' -> do
                                             ed <- ctToElemDesc ct'
          -- TODO: dabei Attributliste zusammenstellen
          -- rekursiver Aufruf:
          -- Liste von Restriktionen merken: rlist
          -- Absteigen in referenzierten ComplexType von dem man weiß, dass es ein SimpleContent-ComplexType ist:
             -- Falls eine Extension:
                -- Falls basis ein ComplexType: rekursiver Aufruf mit rlist
                -- Falls basis kein ComplexType: rstrToSTTF (BaseAttr basis, rlist)
             -- Falls eine Restriction: rlists mergen! (evtl. erst beim Aufstieg)
                -- Falls basis ein ComplexType: rekursiver Aufruf mit mergedRlist
                -- Falls basis kein ComplexType: rstrToSTTF (BaseAttr basis, mergedRlist)
                                             let tf = checkBothSTTF (sttf ed) $ rlistToSTTF rlist
                                             return $ mkSimpleElemDesc (union am $ attrMap ed) tf
          STRAnonymStDecl _ -> mkSimpleElemDesc am <$> rstrToSTTF rstr
      CCont cc      -> do
                       case ccDef cc of -- TODO: ccMixed cc (Maybe String) 
                         CCExt   (n, m) -> case lookup n $ sComplexTypes s of
                                             Nothing  -> return $ mkErrorElemDesc
                                                         "element validation error: illegal type reference in schema file"
                                             Just ct' -> do
                                                         base <- ctToElemDesc ct'
                                                         ed <- ctModelToElemDesc m
                                                         -- TODO: validate extension merge rules
                                                         return $ mkElemDesc (union (attrMap ed) (attrMap base))
                                                                             (mkAlt (contentModel ed) (contentModel base))
                                                                             (union (subElemDesc ed) (subElemDesc base))
                                                                             (checkBothSTTF (sttf base) (sttf ed))
                         CCRestr (n, m) -> case lookup n $ sComplexTypes s of
                                             Nothing  -> return $ mkErrorElemDesc
                                                         "element validation error: illegal type reference in schema file"
                                             Just ct' -> do
                                                         base <- ctToElemDesc ct'
                                                         ed <- ctModelToElemDesc m
                                                         -- TODO: validate restriction merge rules
                                                         return $ mkElemDesc (attrMap ed)
                                                                             (contentModel ed)
                                                                             (subElemDesc ed)
                                                                             (checkBothSTTF (sttf base) (sttf ed))
      NewCT m       -> ctModelToElemDesc m

createElemDesc :: Element -> XSC ElemDesc
createElemDesc (ElRef n)
  = do
    s <- ask
    case lookup n (sElements s) of
           Just e  -> createElemDesc e
           Nothing -> return $ mkErrorElemDesc "element validation error: illegal element reference in schema file"
createElemDesc (ElDef (ElementDef _ tdef))
  = do
    s <- ask
    t <- case tdef of
           ETDTypeAttr r      -> case lookup r (sComplexTypes s) of
                                   Nothing  -> Left <$> lookupSTTF r
                                   Just ctr -> return $ Right ctr
           ETDAnonymStDecl st -> Left <$> stToSTTF st
           ETDAnonymCtDecl ct -> return $ Right ct
    case t of
      Left tf  -> return $ mkSimpleElemDesc empty tf 
      Right ct -> ctToElemDesc ct

-- Every globally defined element can be the root element
createRootDesc :: XSC ElemDesc
createRootDesc
  = do
    s <- ask
    let cm = mkAlts $ map mkElemRE $ keys $ sElements s
    se <- fromList <$> zip (keys (sElements s)) <$> (mapM createElemDesc $ elems $ sElements s)
    -- TODO: add possible namespace-setting attribute to every possible root element's attribute map
    return $ mkElemDesc empty cm se mkNoTextSTTF

--------------------------------------------------------------------------------------

-- Types for validation

type CountingTable = Map QName Int

data SValEnv       = SValEnv
                   { xpath    :: XPath
                   , elemDesc :: ElemDesc
                   }
type XPath         = String
type SValLog       = [(XPath, String)]

type SValResult    = (Bool, SValLog)

type SVal a        = ReaderT SValEnv (WriterT SValLog Identity) a

runSVal :: SValEnv -> SVal a -> (a, SValLog)
runSVal env val = runIdentity $ runWriterT $ runReaderT val env

-- Validation

getReqAttrNames :: AttrMap -> [QName]
getReqAttrNames m = map (\ (n, _) -> n) $ filter (\ (_, (req, _)) -> req) (toList m)

hasReqAttrs :: [QName] -> [QName] -> SVal Bool
hasReqAttrs [] _
  = return True
hasReqAttrs (x:xs) attrs
  = do
    env <- ask
    if x `notElem` attrs
      then do
           tell [((xpath env) ++ "/@" ++ (qualifiedName x), "required attribute is missing.")]
           res <- hasReqAttrs xs attrs
           return (res && False)
      else hasReqAttrs xs attrs

checkAllowedAttrs :: [(QName, String)] -> SVal Bool
checkAllowedAttrs []
  = return True
checkAllowedAttrs ((n, val):xs)
  = do
    env <- ask
    res <- case lookup n $ attrMap $ elemDesc env of
             Nothing      -> do
                             tell [((xpath env) ++ "/@" ++ (qualifiedName n), "attribute not allowed here.")]
                             return False
             Just (_, tf) -> local (const (appendXPath ("/@" ++ (qualifiedName n)) env)) (tf val)
                             -- TODO: can be removed?
                             -- do
                             -- tfRes <- local (const (appendXPath ("/@" ++ (qualifiedName n)) env)) (tf val)
                             -- if not tfRes
                             --   then do
                             --        tell [((xpath env) ++ "/@" ++ (qualifiedName n), "value does not match type.")]
                             --        return tfRes                                    
                             --   else return tfRes
    rest <- checkAllowedAttrs xs
    return (res && rest)

testAttrs :: XmlTree -> SVal Bool
testAttrs e
  = do
    env <- ask
    let attrl = getElemAttrs e
    allowedAttrsRes <- checkAllowedAttrs attrl
    reqAttrsRes <- hasReqAttrs (getReqAttrNames (attrMap $ elemDesc env)) (map fst attrl)
    return (allowedAttrsRes && reqAttrsRes)

testContentModel :: XmlTrees -> SVal Bool
testContentModel t
  = do
    env <- ask
    case matchXmlRegex (contentModel $ elemDesc env) t of
      Nothing -> return True
      Just msg-> do
                 tell [(xpath env ++ "/*", "content does not match content model.\n" ++ msg)]
                 return False

appendXPath :: String -> SValEnv -> SValEnv
appendXPath s env
  = SValEnv ((xpath env) ++ s) $ elemDesc env

newDesc :: ElemDesc -> SValEnv -> SValEnv
newDesc d env
  = SValEnv (xpath env) d

testElemChildren :: CountingTable -> XmlTrees -> SVal Bool
testElemChildren _ []
  = return True
testElemChildren t (x:xs)
  = do
    env <- ask
    let n = getElemName x
    let c = case lookup n t of
              Nothing -> 1
              Just v  -> v+1
    let elemXPath = "/" ++ (qualifiedName n) ++ "[" ++ (show c) ++ "]"
    res <- case lookup n $ subElemDesc $ elemDesc env of
             Nothing -> do
                        tell [((xpath env) ++ elemXPath, "element not allowed here.")]
                        return False
             Just d  -> local (const (appendXPath elemXPath (newDesc d env))) (testElem x)
    rest <- testElemChildren (insert n c t) xs
    return (res && rest)

testElemText :: XmlTrees -> SVal Bool
testElemText t
  = do
    env <- ask
    local (const (appendXPath "/child::text()" env)) $ (sttf $ elemDesc env) $ getCombinedText t -- getTexts instead?

extractElems :: XmlTrees -> (XmlTrees, XmlTrees)
extractElems = partition isElem

testElem :: XmlTree -> SVal Bool
testElem e
  = do
    env <- ask
    case (errmsg $ elemDesc env) of
      Just msg -> do
                  tell [(xpath env, msg)]
                  return False
      Nothing  -> do
                  attrRes <- testAttrs e
                  let content = getElemChildren e
                  contModelRes <- testContentModel content
                  let (tags, text) = extractElems content
                  textRes <- testElemText text
                  tagsRes <- testElemChildren empty tags
                  return (attrRes && contModelRes && textRes && tagsRes)

printSValResult :: SValResult -> IO ()
printSValResult (status, l)
  = do
    if status
      then putStrLn "\nok.\n"
      else putStrLn "\nerrors occurred:\n"
    mapM_ (\ (a, b) -> putStrLn $ a ++ "\n" ++ b ++ "\n") l
    return ()

validateWithSchema :: String -> String -> IO SValResult
validateWithSchema descUri instUri
  = do
    desc <- loadXmlSchema descUri
    case desc of
      Nothing -> return (False, [("/", "Could not process description file.")])
      Just d  -> do
                 inst <- readDoc instUri
                 case inst of
                   Nothing -> return (False, [("/", "Could not process instance file.")])
                   Just i  -> return $ runSVal (SValEnv "" (runXSC d createRootDesc)) (testElem i)

--------------------------------------------------------------------------------------

-- Test setup:

main :: IO ()
main
  = do
    -- argv <- getArgs
    -- (schemaurl, docurl) <- return (argv!!0, argv!!1)

    res <- validateWithSchema "example.xsd" "example.xml"
    printSValResult res

    return ()

