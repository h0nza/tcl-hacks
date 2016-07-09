/*
 * http://findproxyforurl.com/
 * https://www.chromium.org/developers/design-documents/secure-web-proxy
 * http://wiki.squid-cache.org/Features/HTTPS#Encrypted_browser-Squid_connection
 */
function FindProxyForURL(url, host) {
    return "HTTPS localhost:1443";
}
