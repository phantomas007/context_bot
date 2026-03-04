<?php

declare(strict_types=1);

namespace App\MessageHandler;

use App\Entity\Message;
use App\Entity\TelegramGroup;
use App\Entity\User;
use App\Entity\UserGroup;
use App\Message\IncomingTelegramUpdateMessage;
use App\Message\SummaryJobMessage;
use App\Repository\MessageRepository;
use App\Repository\TelegramGroupRepository;
use App\Repository\UserGroupRepository;
use App\Repository\UserRepository;
use Doctrine\DBAL\Exception\UniqueConstraintViolationException;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Symfony\Component\Messenger\MessageBusInterface;

#[AsMessageHandler]
final class MessageSaveHandler
{
    public function __construct(
        private readonly EntityManagerInterface $em,
        private readonly MessageBusInterface $bus,
        private readonly MessageRepository $messageRepository,
        private readonly TelegramGroupRepository $groupRepository,
        private readonly UserRepository $userRepository,
        private readonly UserGroupRepository $userGroupRepository,
    ) {
    }

    public function __invoke(IncomingTelegramUpdateMessage $envelope): void
    {
        // Все операции оборачиваем в одну транзакцию
        $this->em->wrapInTransaction(function() use ($envelope) {

            $update = $envelope->update;
            $telegramMessage = $update['message'] ?? null;
            if (!\is_array($telegramMessage)) return;

            $chat = $telegramMessage['chat'] ?? null;
            if (!\is_array($chat) || !\in_array($chat['type'] ?? '', ['group', 'supergroup'], true)) return;

            $text = $telegramMessage['text'] ?? null;
            if (!\is_string($text) || $text === '') return;

            $from = $telegramMessage['from'] ?? null;

            $telegramChatId = (int) $chat['id'];
            $telegramMessageId = (int) $telegramMessage['message_id'];
            $messageDate = new \DateTimeImmutable('@' . (int) $telegramMessage['date']);

            // Создаем или обновляем группу
            $group = $this->upsertGroup($telegramChatId, $chat['title'] ?? null);

            $user = null;
            if (\is_array($from) && !($from['is_bot'] ?? false)) {
                // Создаем или обновляем пользователя
                $user = $this->upsertUser($from);
                $this->upsertUserGroup($user, $group);
            }

            // Создаем сообщение
            $message = new Message(
                telegramMessageId: $telegramMessageId,
                group: $group,
                telegramUserId: $user?->getTelegramUserId(),
                username: $from['username'] ?? $from['first_name'] ?? null,
                text: $text,
                createdAt: $messageDate,
            );
            $this->em->persist($message);

            try {
                // Один flush для всех изменений
                $this->em->flush();
            } catch (UniqueConstraintViolationException) {
                // Если сообщение уже есть — тихо выходим
                $this->em->clear();
                return;
            }

            // Проверяем порог для summary ! убрать !
            $this->checkSummaryThreshold($group);
        });
    }

    private function upsertGroup(int $telegramChatId, ?string $title): TelegramGroup
    {
        $group = $this->groupRepository->findOneBy(['telegramChatId' => $telegramChatId]);

        if (!$group) {
            $group = new TelegramGroup(telegramChatId: $telegramChatId, title: $title);
            $this->em->persist($group);
        } elseif ($title && $group->getTitle() !== $title) {
            $group->updateTitle($title);
        }

        return $group;
    }

    /** @param array<string,mixed> $from */
    private function upsertUser(array $from): User
    {
        $telegramUserId = (int) $from['id'];
        $user = $this->userRepository->findOneBy(['telegramUserId' => $telegramUserId]);

        if (!$user) {
            $user = new User(
                telegramUserId: $telegramUserId,
                username: $from['username'] ?? null,
                firstName: $from['first_name'] ?? null,
            );
            $this->em->persist($user);
        }

        return $user;
    }

    private function upsertUserGroup(User $user, TelegramGroup $group): void
    {
        $existing = $this->userGroupRepository->findOneBy(['user' => $user, 'group' => $group]);
        if (!$existing) {
            $this->em->persist(new UserGroup($user, $group));
        }
    }

    /**
     * Уберем сделаем  отдельной консольной командой!   
     * 
     * @param TelegramGroup $group
     * 
     * @return void
     */
    private function checkSummaryThreshold(TelegramGroup $group): void
    {
        $count = $this->messageRepository->countUnsummarized($group);
        if ($count >= 100 && $count % 100 === 0) {
            $this->bus->dispatch(new SummaryJobMessage($group->getId() ?? 0));
        }
    }
}