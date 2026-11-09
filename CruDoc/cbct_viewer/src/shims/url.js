// Node's "url" is not available in the browser. @oozcitak/url (xmlbuilder2's
// DOM) imports it only for domainToASCII / domainToUnicode in host parsing,
// which this viewer never reaches.
export const domainToASCII = (domain) => String(domain).toLowerCase();
export const domainToUnicode = (domain) => String(domain);
export default { domainToASCII, domainToUnicode };
