<?php

declare(strict_types=1);

namespace App\Controller;

use App\Message\IncomingTelegramUpdateMessage;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Routing\Attribute\Route;

class TelegramWebhookController
{
    public function __construct(
        private readonly MessageBusInterface $bus,
        #[Autowire(env: 'TELEGRAM_WEBHOOK_SECRET')]
        private readonly string $webhookSecret,
    ) {
    }

    #[Route('/api/telegram/webhook', name: 'telegram_webhook', methods: ['POST'])]
    public function __invoke(Request $request): JsonResponse
    {
        if (!$this->isValidRequest($request)) {
            return new JsonResponse(['ok' => false, 'error' => 'Unauthorized'], 401);
        }

        $data = json_decode($request->getContent(), true);
        if (!is_array($data)) {
            return new JsonResponse(['ok' => true]);
        }

        $this->bus->dispatch(new IncomingTelegramUpdateMessage($data));

        return new JsonResponse(['ok' => true]);
    }

    private function isValidRequest(Request $request): bool
    {
        if ($this->webhookSecret === '') {
            return true;
        }

        $provided = $request->headers->get('X-Telegram-Bot-Api-Secret-Token', '');

        return hash_equals($this->webhookSecret, $provided);
    }
}
