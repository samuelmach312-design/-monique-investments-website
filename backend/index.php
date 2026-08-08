<?php
require_once 'Mpesa.php';
header('Content-Type: application/json');

try {
    $input = json_decode(file_get_contents('php://input'), true);

    $phone = $input['phone']?? null;
    $amount = $input['amount']?? null;
    $reference = $input['reference']?? 'Order123';

    if (!$phone ||!$amount) {
        http_response_code(400);
        echo json_encode(['error' => 'Phone and amount required']);
        exit;
    }

    $mpesa = new Mpesa();
    $result = $mpesa->stkPush(
        $phone,
        $amount,
        $reference,
        'Payment for '. $reference
    );

    echo json_encode([
        'success' => true,
        'message' => 'STK Push sent. Check your phone.',
        'data' => $result
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}