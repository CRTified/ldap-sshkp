{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings #-}

module Lib
  ( run,
  )
where

import Control.Monad (when)
import qualified Data.ByteString as B
import Data.Int (Int32)
import Data.List (find)
import Data.Maybe (fromJust, fromMaybe, isJust)
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Word (Word16)
import Ldap.Client (Filter ((:=)), SearchEntry (..))
import qualified Ldap.Client as Ldap
import System.Console.CmdArgs (argPos, details, explicit, groupname, help, name, program, summary, typ, (&=))
import qualified System.Console.CmdArgs as CA
import Text.Read (readMaybe)

data SearchScope = BaseObject | SingleLevel | WholeSubtree deriving (Show, CA.Data, CA.Typeable)

data Config = Config
  { host :: String,
    port :: Word16,
    useTLS :: Bool,
    useInsecureTLS :: Bool,
    bindDn :: Maybe T.Text,
    bindPass :: Maybe T.Text,
    baseDn :: T.Text,
    searchAttr :: T.Text,
    valueAttr :: T.Text,
    timeout :: Int32,
    target :: Maybe T.Text,
    searchScope :: SearchScope
  }
  deriving (Show, CA.Data, CA.Typeable)

ldapsshkp :: Config
ldapsshkp =
  Config
    { host = "localhost" &= help "LDAP Hostname (Default: localhost)" &= groupname "LDAP settings",
      port = 389 &= help "LDAP port (Default: 368)",
      useTLS = False &= help "Uses TLS for LDAP connection",
      useInsecureTLS = False &= help "Do not verify TLS certificates",
      timeout = 10 &= help "Timeout for LDAP search",
      bindDn = Nothing &= help "DN used to bind against LDAP",
      bindPass = Nothing &= help "Password used for binding",
      baseDn = "" &= help "DN used as base for searching" &= groupname "Search Settings",
      searchAttr = "uid" &= help "Attribute for matching (Default: uid)",
      valueAttr = "sshPublicKey" &= help "Attribute containing public keys (Default: sshPublicKey)",
      target = Nothing &= argPos 0 &= typ "USER",
      searchScope =
        CA.enum
          [ SingleLevel &= explicit &= name "single-level" &= help "Constrain search to immediate subordinates of baseDN (Default)" &= groupname "Search Scopes (Only one possible)",
            BaseObject &= explicit &= name "base-object" &= help "Constrain search to the baseDN",
            WholeSubtree &= explicit &= name "whole-subtree" &= help "Constrain search to all subordinates of baseDN"
          ]
    }
    &= help "Fetches SSH public keys for USER from the specified LDAP"
    &= summary "ldap-sshkp v0.1.0.0, (C) Carl Richard Theodor Schneider"
    &= program "ldap-sshkp"
    &= details ["ldap-sshkp fetches SSH public keys from LDAP."]

showFoundKeys :: Ldap.Attr -> Ldap.SearchEntry -> T.Text
showFoundKeys vAttr (SearchEntry (Ldap.Dn dn) attrs) = T.unlines $ T.append "# " dn : keys
  where
    rawKeys = case find (\x -> vAttr == fst x) attrs of
      Just (_, vs) -> B.intercalate "\n" vs
      Nothing -> ""
    keys = map T.strip $ T.lines $ decodeUtf8 rawKeys

run :: IO ()
run = do
  conf <- CA.cmdArgs ldapsshkp

  case target conf of
    Nothing -> return ()
    Just t -> do
      result <-
        Ldap.with
          (buildHost conf)
          (buildPort $ port conf)
          ( \conn -> do
              when (isJust (bindDn conf) && isJust (bindPass conf)) $ Ldap.bind conn (Ldap.Dn $ fromJust $ bindDn conf) (Ldap.Password $ encodeUtf8 $ fromJust $ bindPass conf)
              let selectedScope = Ldap.scope $ case searchScope conf of
                    BaseObject -> Ldap.BaseObject
                    SingleLevel -> Ldap.SingleLevel
                    WholeSubtree -> Ldap.WholeSubtree
              Ldap.search conn (Ldap.Dn $ baseDn conf) (selectedScope <> Ldap.time (timeout conf)) (Ldap.Attr (searchAttr conf) := encodeUtf8 t) [Ldap.Attr $ valueAttr conf]
          )
      case result of
        -- Prepend "#" to error to prevent (unlikely) faulty interpretation as public key
        Left err -> putStrLn $ "# " ++ show err
        Right val -> do
          mapM_ (putStrLn . T.unpack . showFoundKeys (Ldap.Attr $ valueAttr conf)) val
  where
    buildHost :: Config -> Ldap.Host
    buildHost conf =
      if useTLS conf
        then
          Ldap.Tls
            (host conf)
            ( if useInsecureTLS conf
                then Ldap.insecureTlsSettings
                else Ldap.defaultTlsSettings
            )
        else Ldap.Plain (host conf)
    buildPort :: Word16 -> Ldap.PortNumber
    buildPort p = fromMaybe 389 ((readMaybe . show) p)
