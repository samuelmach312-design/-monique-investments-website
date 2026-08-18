<?php
require_once 'Mpesa.php';

// Log callback for debugging
file_put_contents('mpesa_callbacks.log', date('Y-m-d H:i:s'). ' - '. file_get_contents('php://input'). "\n", FILE_APPEND);

$data = json_decode(file_get_contents('php://input'), true);
$callback = $data['Body']['stkCallback']?? null;

if (!$callback) {
    http_response_code(400);
    exit('Invalid callback');
}

$resultCode = $callback['ResultCode'];
$merchantRequestID = $callback['MerchantRequestID'];
$checkoutRequestID = $callback['CheckoutRequestID'];

if ($resultCode == 0) {
    // Payment successful
    $metadata = $callback['CallbackMetadata']['Item'];
    $amount = $metadata[0]['Value'];
    $mpesaReceiptNumber = $metadata[1]['Value'];
    $transactionDate = $metadata[3]['Value'];
    $phoneNumber = $metadata[4]['Value'];

    // TODO: Update your database, mark order as paid
    // saveToDatabase($checkoutRequestID, $mpesaReceiptNumber, $amount, $phoneNumber);

    echo json_encode(['ResultCode' => 0, 'ResultDesc' => 'Success']);
} else {
    // Payment failed or cancelled
    $resultDesc = $callback['ResultDesc'];

    // TODO: Log failed payment, update order status
    // logFailedPayment($checkoutRequestID, $resultCode, $resultDesc);

    echo json_encode(['ResultCode' => 0, 'ResultDesc' => 'Failed']);
}