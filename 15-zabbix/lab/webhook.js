// Script du media type « Webhook » (Alerts → Media types → Create media type → Type: Webhook).
// Paramètres à déclarer : url = http://alert-sink:8080/ ; subject = {ALERT.SUBJECT} ;
//                         message = {ALERT.MESSAGE} ; severity = {EVENT.SEVERITY}
// Le même principe sert à créer un ticket ServiceNow, poster dans Teams, appeler PagerDuty…
var params = JSON.parse(value);
var req = new HttpRequest();
req.addHeader('Content-Type: application/json');

var resp = req.post(params.url, JSON.stringify({
    subject: params.subject,
    message: params.message,
    severity: params.severity
}));

if (req.getStatus() !== 200) {
    throw 'Échec de la notification : HTTP ' + req.getStatus() + ' ' + resp;
}
return 'OK';
