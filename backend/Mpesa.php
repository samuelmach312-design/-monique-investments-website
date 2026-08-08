<?php
class Mpesa {
    private $consumerKey;
    private $consumerSecret;
    private $shortcode;
    private $passkey;
    private $env;
    private $callbackUrl;
    private $timeoutUrl;
    private $accessToken;

    public function __construct() {
        $this->loadEnv();
        $this->consumerKey = $_ENV['MPESA_CONSUMER_KEY'];
        $this->consumerSecret = $_ENV['MPESA_CONSUMER_SECRET'];
        $this->shortcode = $_ENV['MPESA_SHORTCODE'];
        $this->passkey = $_ENV['MPESA_PASSKEY'];
        $this->env = $_ENV['MPESA_ENV']?? 'sandbox';
        $this->callbackUrl = $_ENV['MPESA_CALLBACK_URL'];
        $this->timeoutUrl = $_ENV['MPESA_TIMEOUT_URL'];
    }

    private function loadEnv() {
        if (!file_exists(__DIR__. '/.env')) {
            throw new Exception('.env file not found');
        }
        $lines = file(__DIR__. '/.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $line) {
            if (strpos(trim($line), '#') === 0) continue;
            list($name, $value) = explode('=', $line, 2);
            $_ENV[trim($name)] = trim($value);
        }
    }

    private function getBaseUrl() {
        return $this->env === 'production'
           ? 'https://api.safaricom.co.ke'
            : 'https://sandbox.safaricom.co.ke';
    }

    private function generateAccessToken() {
        $url = $this->getBaseUrl(). '/oauth/v1/generate?grant_type=client_credentials';
        $credentials = base64_encode($this->consumerKey. ':'. $this->consumerSecret);

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_HTTPHEADER => ['Authorization: Basic '. $credentials],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_TIMEOUT => 30
        ]);

        $response = curl_exec($ch);
        if (curl_errno($ch)) {
            throw new Exception('cURL Error: '. curl_error($ch));
        }
        curl_close($ch);

        $result = json_decode($response);
        if (!isset($result->access_token)) {
            throw new Exception('Failed to get access token: '. $response);
        }

        $this->accessToken = $result->access_token;
        return $this->accessToken;
    }

    private function generatePassword() {
        $timestamp = date('YmdHis');
        $password = base64_encode($this->shortcode. $this->passkey. $timestamp);
        return ['password' => $password, 'timestamp' => $timestamp];
    }

    public function stkPush($phone, $amount, $accountReference, $transactionDesc) {
        $this->generateAccessToken();
        $url = $this->getBaseUrl(). '/mpesa/stkpush/v1/processrequest';
        $auth = $this->generatePassword();

        // Format phone: 2547XXXXXXXX
        $phone = preg_replace('/^0/', '254', $phone);
        $phone = preg_replace('/^\+/', '', $phone);

        $payload = [
            'BusinessShortCode' => $this->shortcode,
            'Password' => $auth['password'],
            'Timestamp' => $auth['timestamp'],
            'TransactionType' => 'CustomerPayBillOnline',
            'Amount' => $amount,
            'PartyA' => $phone,
            'PartyB' => $this->shortcode,
            'PhoneNumber' => $phone,
            'CallBackURL' => $this->callbackUrl,
            'AccountReference' => $accountReference,
            'TransactionDesc' => $transactionDesc
        ];

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer '. $this->accessToken,
                'Content-Type: application/json'
            ],
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => json_encode($payload),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_TIMEOUT => 60
        ]);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

        if (curl_errno($ch)) {
            throw new Exception('cURL Error: '. curl_error($ch));
        }
        curl_close($ch);

        $result = json_decode($response, true);

        if ($httpCode!== 200) {
            throw new Exception('STK Push failed: '. $response);
        }

        return $result;
    }
}