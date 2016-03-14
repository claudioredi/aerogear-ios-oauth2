//
//  OpenStackOauth2Module.swift
//  AeroGearOAuth2
//
//  Created by Claudio on 9/18/15.
//  Copyright © 2015 aerogear. All rights reserved.
//

import UIKit

public class OpenStackOAuth2Module: OAuth2Module {
    
    public override func revokeAccess(completionHandler: (AnyObject?, NSError?) -> Void) {
        // return if not yet initialized
        if (self.oauth2Session.accessToken == nil) {
            return;
        }
        var paramDict:[String:String] = [ "client_id": config.clientId]
        if (self.oauth2Session.refreshToken != nil) {
            paramDict["refresh_token"] = self.oauth2Session.refreshToken!
        }
        http.POST(config.revokeTokenEndpoint!, parameters: paramDict, completionHandler: { (response, error) in
            if (error != nil) {
                completionHandler(nil, error)
                return
            }
            
            self.oauth2Session.clearTokens()
            completionHandler(response, nil)
        })
    }
    
    /**
    Gateway to login with OpenIDConnect
    
    :param: completionHandler A block object to be executed when the request operation finishes.
    */
    public override func login(completionHandler: (AnyObject?, OpenIDClaim?, NSError?) -> Void) {
        var openIDClaims: OpenIDClaim?
        
        // hotfix to clear persistent tokens in keychain on login
        self.oauth2Session.clearTokens()
        
        super.requestAccess { (response: AnyObject?, error: NSError?) -> Void in
            if (error != nil) {
                completionHandler(nil, nil, error)
                return
            }
            
            if let unwrappedResponse = response as? [String: AnyObject] {
                let accessToken: String = unwrappedResponse["access_token"] as! String
                let refreshToken: String? = unwrappedResponse["refresh_token"] as? String
                let expiration = unwrappedResponse["expires_in"] as? NSNumber
                let exp: String? = expiration?.stringValue
                let expirationRefresh = unwrappedResponse["refresh_expires_in"] as? NSNumber
                let expRefresh = expirationRefresh?.stringValue
                
                // in Keycloak refresh token get refreshed every time you use them
                self.oauth2Session.saveAccessToken(accessToken, refreshToken: refreshToken, accessTokenExpiration: exp, refreshTokenExpiration: expRefresh)
                if let idToken =  unwrappedResponse["id_token"] as? String {
                    let token = self.decode(idToken)
                    if let decodedToken = token {
                        openIDClaims = OpenIDClaim(fromDict: decodedToken)
                    }
                }
                completionHandler(accessToken, openIDClaims, nil)
            }
            else {
                if let accessToken = response as? String {
                    completionHandler(accessToken, nil, nil)
                }
            }
        }
    }
    
    /**
     Gateway to request authorization access.
     
     :param: completionHandler A block object to be executed when the request operation finishes.
     */
    public override func requestAccess(completionHandler: (AnyObject?, NSError?) -> Void) {
        if (self.oauth2Session.accessToken != nil && self.oauth2Session.tokenIsNotExpired()) {
            // we already have a valid access token, nothing more to be done
            completionHandler(self.oauth2Session.accessToken!, nil);
        } else if (self.oauth2Session.refreshToken != nil && self.oauth2Session.refreshTokenIsNotExpired()) {
            // need to refresh token
            self.refreshAccessToken(completionHandler)
        } else if (self.config.isServiceAccount) {
            self.loginClientCredentials() { (accessToken, claims, error) in
                completionHandler(accessToken, error)
            }
        } else {
            // error, must enforce user to request interactive login
            completionHandler(nil, NSError(domain: "OpenStackOAuth2Module", code: 8, userInfo: ["OpenStack OAuth2 Module": "User must do interactive login"]))
        }
    }
    
    /**
    Exchange an authorization code for an access token.
    
    :param: code the 'authorization' code to exchange for an access token.
    :param: completionHandler A block object to be executed when the request operation finishes.
    */
    public override func exchangeAuthorizationCodeForAccessToken(code: String, completionHandler: (AnyObject?, NSError?) -> Void) {
        var paramDict: [String: String] = ["code": code, "client_id": config.clientId, "redirect_uri": config.redirectURL, "grant_type":"authorization_code"]
        
        if let unwrapped = config.clientSecret {
            paramDict["client_secret"] = unwrapped
        }
        
        http.POST(config.accessTokenEndpoint, parameters: paramDict, completionHandler: {(responseObject, error) in
            if (error != nil) {
                completionHandler(nil, error)
                return
            }
            
            if let unwrappedResponse = responseObject as? [String: AnyObject] {
                completionHandler(unwrappedResponse, nil)
            }
        })
    }
    
    func decode(token: String) -> [String: AnyObject]? {
        let string = token.componentsSeparatedByString(".")
        let toDecode = string[1] as String
        
        
        var stringtoDecode: String = toDecode.stringByReplacingOccurrencesOfString("-", withString: "+") // 62nd char of encoding
        stringtoDecode = stringtoDecode.stringByReplacingOccurrencesOfString("_", withString: "/") // 63rd char of encoding
        switch (stringtoDecode.utf16.count % 4) {
        case 2: stringtoDecode = "\(stringtoDecode)=="
        case 3: stringtoDecode = "\(stringtoDecode)="
        default: // nothing to do stringtoDecode can stay the same
            print("")
        }
        let dataToDecode = NSData(base64EncodedString: stringtoDecode, options: [])
        let base64DecodedString = NSString(data: dataToDecode!, encoding: NSUTF8StringEncoding)
        
        var values: [String: AnyObject]?
        if let string = base64DecodedString {
            if let data = string.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true) {
                values = try! NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.AllowFragments) as? [String : AnyObject]
            }
        }
        return values
    }
}

