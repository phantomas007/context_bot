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
        $update = $envelope->update;

        $telegramMessage = $update['message'] ?? null;
        if (!is_array($telegramMessage)) {
            return;
        }

        $chat = $telegramMessage['chat'] ?? null;
        if (!is_array($chat) || !in_array($chat['type'] ?? '', ['group', 'supergroup'], true)) {
            return;
        }

        $text = $telegramMessage['text'] ?? null;
        if (!is_string($text) || $text === '') {
            return;
        }

        $from = $telegramMessage['from'] ?? null;
        $telegramChatId = (int) $chat['id'];
        $telegramMessageId = (int) $telegramMessage['message_id'];
        $messageDate = new \DateTimeImmutable('@' . (int) $telegramMessage['date']);

        $group = $this->upsertGroup($telegramChatId, $chat['title'] ?? null);

        if (is_array($from) && !($from['is_bot'] ?? false)) {
            $user = $this->upsertUser($from);
            $this->upsertUserGroup($user, $group);
        }

        $saved = $this->saveMessage(
            telegramMessageId: $telegramMessageId,
            group: $group,
            telegramUserId: is_array($from) ? (int) $from['id'] : null,
            username: is_array($from) ? ($from['username'] ?? $from['first_name'] ?? null) : null,
            text: $text,
            createdAt: $messageDate,
        );

        if ($saved) {
            $this->checkSummaryThreshold($group);
        }
    }

    private function upsertGroup(int $telegramChatId, ?string $title): TelegramGroup
    {
        $group = $this->groupRepository->findOneBy(['telegramChatId' => $telegramChatId]);

        if ($group === null) {
            $group = new TelegramGroup(telegramChatId: $telegramChatId, title: $title);
            $this->em->persist($group);
            $this->em->flush();

            return $group;
        }

        if ($title !== null && $group->getTitle() !== $title) {
            $group->updateTitle($title);
            $this->em->flush();
        }

        return $group;
    }

    /** @param array<string, mixed> $from */
    private function upsertUser(array $from): User
    {
        $telegramUserId = (int) $from['id'];
        $user = $this->userRepository->findOneBy(['telegramUserId' => $telegramUserId]);

        if ($user === null) {
            $user = new User(
                telegramUserId: $telegramUserId,
                username: $from['username'] ?? null,
                firstName: $from['first_name'] ?? null,
            );
            $this->em->persist($user);
            $this->em->flush();
        }

        return $user;
    }

    private function upsertUserGroup(User $user, TelegramGroup $group): void
    {
        $existing = $this->userGroupRepository->findOneBy(['user' => $user, 'group' => $group]);

        if ($existing === null) {
            $this->em->persist(new UserGroup($user, $group));
            $this->em->flush();
        }
    }

    private function saveMessage(
        int $telegramMessageId,
        TelegramGroup $group,
        ?int $telegramUserId,
        ?string $username,
        string $text,
        \DateTimeImmutable $createdAt,
    ): bool {
        $existing = $this->messageRepository->findOneBy([
            'telegramMessageId' => $telegramMessageId,
            'group' => $group,
        ]);

        if ($existing !== null) {
            return false;
        }

        $this->em->persist(new Message(
            telegramMessageId: $telegramMessageId,
            group: $group,
            telegramUserId: $telegramUserId,
            username: $username,
            text: $text,
            createdAt: $createdAt,
        ));
        $this->em->flush();

        return true;
    }

    private function checkSummaryThreshold(TelegramGroup $group): void
    {
        $count = $this->messageRepository->countUnsummarized($group);

        if ($count > 0 && $count % 100 === 0) {
            $this->bus->dispatch(new SummaryJobMessage($group->getId() ?? 0));
        }
    }
}
