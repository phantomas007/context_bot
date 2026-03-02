<?php

declare(strict_types=1);

namespace App\Message;

final readonly class PublishJobMessage
{
    public function __construct(
        public int $contextId,
    ) {
    }
}
