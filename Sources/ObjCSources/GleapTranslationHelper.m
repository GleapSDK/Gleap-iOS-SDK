//
//  GleapTranslationHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 17.02.21.
//

#import "GleapTranslationHelper.h"
#import "GleapCore.h"

@implementation GleapTranslationHelper

+ (NSDictionary *)getTranslation {
    NSString *lang = [[Gleap sharedInstance].language lowercaseString];
    if (lang.length > 2) {
        lang = [lang substringToIndex: 2];
    }
    
    if ([lang isEqualToString: @"es"]) {
        return @{
            @"ok": @"Ok",
            @"report_failed": @"Se ha producido un error.",
            @"report_failed_title": @"Error de conexión 🤕",
        };
    }
    
    if ([lang isEqualToString: @"it"]) {
        return @{
            @"ok": @"Ok",
            @"report_failed": @"Qualcosa è andato storto.",
            @"report_failed_title": @"Errore di connessione 🤕",
        };
    }
    
    if ([lang isEqualToString: @"fr"]) {
        return @{
            @"ok": @"Ok",
            @"report_failed": @"Oups, il y a eu un problème.",
            @"report_failed_title": @"Erreur de connexion 🤕",
        };
    }
    
    if ([lang isEqualToString: @"de"]) {
        return @{
            @"ok": @"Ok",
            @"report_failed": @"Ups, da ist etwas schief gelaufen.",
            @"report_failed_title": @"Verbindungsfehler 🤕",
        };
    }
    
    if ([lang isEqualToString: @"nl"]) {
        return @{
            @"ok": @"Ok",
            @"report_failed": @"Oeps, er gaat helaas iets mis",
            @"report_failed_title": @"Verbindingsfout 🤕",
        };
    }
    
    if ([lang isEqualToString: @"cz"]) {
        return @{
            @"ok": @"Ok",
            @"report_failed": @"Ups, něco se pokazilo.",
            @"report_failed_title": @"Chyba připojení 🤕",
        };
    }
    
    return @{
        @"ok": @"Ok",
        @"report_failed": @"Ups, something went wrong.",
        @"report_failed_title": @"Connection error 🤕",
    };
}

+ (NSString *)localizedString:(NSString *)string {
    NSDictionary *translation = GleapTranslationHelper.getTranslation;
    
    NSString *translatedString = [translation objectForKey: string];
    if (translatedString) {
        return translatedString;
    }
    
    return string;
}

@end
