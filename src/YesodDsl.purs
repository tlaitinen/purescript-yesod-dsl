module YesodDsl where
import Prelude 
import Data.Argonaut.Encode (class EncodeJson, encodeJson)
import Data.Argonaut.Decode (class DecodeJson, decodeJson)
import Data.Argonaut.Core (Json, isNull, foldJsonObject, jsonEmptyObject)
import Data.Argonaut.Combinators ((~>), (:=), (.?))
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Generic (class Generic, gCompare, gEq, gShow)
import Data.Either (Either(..))
import Data.URI.Types as URIT
import Data.Array ((!!))
import Data.List as L
import Data.String as DS
import Data.Date as DD
import Data.String.Regex as R
import Data.Int as I
import Data.StrMap as SM
import Data.Tuple (Tuple(..))
import Control.MonadPlus (guard)
import qualified Control.Monad.Aff as Aff
import Network.HTTP.Affjax as A
import Network.HTTP.RequestHeader as A
import Data.BigInt as BI
import Control.Alt ((<|>))
foreign import s2nImpl :: (Number -> Maybe Number) -> Maybe Number -> String -> Maybe Number

foreign import jsDateToISOString :: DD.JSDate -> String

stringToNumber :: String -> Maybe Number
stringToNumber = s2nImpl Just Nothing

newtype TimeOfDay = TimeOfDay Number

derive instance genericTimeOfDay :: Generic TimeOfDay

timeOfDayRegex :: R.Regex
timeOfDayRegex = R.regex "([0-1][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9]|60)(\\.\\d+)?" R.noFlags

instance showTimeOfDay :: Show TimeOfDay where
    show (TimeOfDay secs) = DS.joinWith ":" [h,zp m++m,zp s++s] ++ fromMaybe "" frac
        where
            ss = I.floor secs
            h = show $ ss `div` 3600
            m = show $ (ss `div` 60) `mod` 60
            zp x = if DS.length x < 2 then "0" else ""
            s = show $ ss `mod` 60
            r = secs - I.toNumber ss
            frac 
                | r > 0.0 = Just $ show r
                | otherwise = Nothing


instance eqTimeOfDay :: Eq TimeOfDay where
    eq = gEq

instance ordTimeOfDay :: Ord TimeOfDay where
    compare = gCompare

instance decodeJsonTimeOfDay :: DecodeJson TimeOfDay where
    decodeJson json = do
        x <- decodeJson json
        fromMaybe (Left $ "Invalid TimeOfDay: " ++ x) $ do
            r <- R.match timeOfDayRegex x
            h <- parseInt r 1
            m <- parseInt r 2
            s <- parseInt r 3
            Just $ pure $ TimeOfDay $ secs h m s + frac (r !! 4)
        where
            parseInt r idx = do
                me <- r !! idx
                e <- me
                I.fromString e
            secs h m s = I.toNumber $ h * 3600 + m * 60 + s
            frac (Just mms) = fromMaybe 0.0 $ do
                mss <- mms
                ms <- stringToNumber mss
                Just $ ms
            frac Nothing       = 0.0

instance encodeJsonTimeOfDay :: EncodeJson TimeOfDay where
    encodeJson s = encodeJson $ show s
data Day = Day Int Int Int

derive instance genericDay :: Generic Day

dayRegex :: R.Regex
dayRegex = R.regex "([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])" R.noFlags

instance showDay :: Show Day where
    show = gShow

instance eqDay :: Eq Day where
    eq = gEq

instance ordDay :: Ord Day where
    compare = gCompare

instance decodeJsonDay :: DecodeJson Day where
    decodeJson json = do
        x <- decodeJson json
        fromMaybe (Left $ "Invalid Day: " ++ x) $ do
            r <- R.match dayRegex x
            y <- parseInt r 1
            m <- parseInt r 2
            d <- parseInt r 3
            Just $ pure $ Day y m d
        where
            parseInt r idx = do
                me <- r !! idx
                e <- me
                I.fromString e
          
instance encodeJsonDay :: EncodeJson Day where
    encodeJson (Day y m d) = encodeJson $ DS.joinWith "-" [ys, ms, ds]
        where
            ys = show y
            ms = pfxZero m
            ds = pfxZero d
            pfxZero v = (if v < 10 then "0" else "") ++ show v
                 

newtype UTCTime = UTCTime DD.Date


instance showUTCTime :: Show UTCTime where
    show (UTCTime d)= show d

instance eqUTCTime :: Eq UTCTime where
    eq (UTCTime d1) (UTCTime d2) = d1 `eq` d2

instance ordUTCTime :: Ord UTCTime where
    compare (UTCTime d1) (UTCTime d2) = compare d1 d2

instance decodeJsonUTCTime :: DecodeJson UTCTime where
    decodeJson json = do
        x <- decodeJson json
        case DD.fromString x of
            Just d -> pure $ UTCTime d
            Nothing -> Left $ "Invalid UTCTime: " ++ x
            
instance encodeJsonUTCTime :: EncodeJson UTCTime where
    encodeJson (UTCTime d) = encodeJson $ jsDateToISOString $ DD.toJSDate d

newtype BigIntP = BigIntP BI.BigInt

instance decodeJsonBigIntP :: DecodeJson BigIntP where
    decodeJson json = (do
            x <- decodeJson json
            case BI.fromString x of
                Just i -> pure $ BigIntP i
                Nothing -> Left $ "Invalid bigInt: " ++ x)
        <|> (do
            x <- decodeJson json
            pure $ BigIntP $ BI.fromInt x)

instance encodeJsonBigIntP :: EncodeJson BigIntP where
    encodeJson (BigIntP i) = encodeJson $ BI.toString i



data Key record = Key Number

derive instance genericKey :: Generic (Key record)

instance showKey :: Show (Key record) where
    show (Key n) = DS.takeWhile (/= '.') $ show n

instance eqKey :: Eq (Key record) where
    eq = gEq

instance ordKey :: Ord (Key record) where
    compare = gCompare

instance decodeJsonKey :: DecodeJson (Key record) where
    decodeJson json = do
        x <- decodeJson json
        pure $ Key x

instance encodeJsonKey :: EncodeJson (Key record) where
    encodeJson (Key x) = encodeJson x



data Result record = Result (Array record) Int

instance functorResult :: Functor Result where
  map f (Result as b) = Result (f <$> as) b

instance decodeJsonResult :: (DecodeJson record) => DecodeJson (Result record) where
    decodeJson json = do
        obj <- decodeJson json
        result <- obj .? "result"
        recs <- decodeJson result
        totalCount <- obj .? "totalCount"

        pure $ Result recs totalCount

class ToURIQuery a where
    toURIQuery :: a -> URIT.Query

instance toURIQueryEncodeJson :: (EncodeJson a) => ToURIQuery a where
    toURIQuery = URIT.Query <<< SM.fromList <<< (foldJsonObject L.Nil f) <<< encodeJson
        where
            f o = do
                Tuple k v <- SM.toList o
                guard $ not $ isNull v
                return $ Tuple k (Just $ show v)

data SortDir = Asc | Desc

instance encodeJsonSortDir :: EncodeJson SortDir where
    encodeJson sd = encodeJson $ case sd of
        Asc -> "ASC"
        Desc -> "DESC"        

data SortField a = SortField a SortDir

instance encodeJsonSortField :: (EncodeJson a) => EncodeJson (SortField a) where
    encodeJson (SortField f sd) = do
        "field" := f
        ~> "direction" := sd
        ~> jsonEmptyObject

data FilterOp = Like | Ilike | Is | IsNot | Eq | Neq | Lt | Gt | Le | Ge

derive instance genericFilterOp :: Generic FilterOp

instance eqFilterOp :: Eq FilterOp where
    eq = gEq

instance ordFilterOp :: Ord FilterOp where
    compare = gCompare

instance encodeJsonFilterOp :: EncodeJson FilterOp where
    encodeJson op = encodeJson $ case op of
        Like -> "like"
        Ilike -> "ilike"
        Is -> "is"
        IsNot -> "is not"
        Eq -> "eq"
        Neq -> "neq"
        Lt -> "lt"
        Gt -> "gt"
        Le -> "le"
        Ge -> "ge"

class YesodDslFilter a where
    yesodDslFilterField :: a -> String
    yesodDslFilterOp    :: a -> FilterOp
    yesodDslFilterValue :: a -> Json

newtype YesodDslFilterP a = YesodDslFilterP a

instance encodeJsonYesodDslFilterP :: (YesodDslFilter a) => EncodeJson (YesodDslFilterP a) where
    encodeJson (YesodDslFilterP f) = do
        "field"         := yesodDslFilterField f
        ~> "comparison" := yesodDslFilterOp f
        ~> "value"      := yesodDslFilterValue f
        ~> jsonEmptyObject

class YesodDslRequest (r :: * -> *) o where
    yesodDslRequest       :: A.URL -> Array A.RequestHeader -> r o -> A.AffjaxRequest Json
    yesodDslParseResponse :: r o -> A.AffjaxResponse Json -> Either String o
   
runYesodDslRequest :: ∀ e r o. YesodDslRequest r o => A.URL -> Array A.RequestHeader -> r o -> Aff.Aff (ajax :: A.AJAX | e) (Tuple (Either String o) (A.AffjaxResponse Json))
runYesodDslRequest baseUrl headers req = do
    resp <- A.affjax $ yesodDslRequest baseUrl headers req
    pure $ Tuple (yesodDslParseResponse req resp) resp

