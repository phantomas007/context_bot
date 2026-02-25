<?php

declare(strict_types=1);

namespace App\DataFixtures;

use App\Entity\Category;
use App\Entity\Post;
use App\Entity\User;
use Doctrine\Bundle\FixturesBundle\Fixture;
use Doctrine\Persistence\ObjectManager;
use Faker\Factory;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;
use Symfony\Component\String\Slugger\AsciiSlugger;

class AppFixtures extends Fixture
{
    public function __construct(
        private readonly UserPasswordHasherInterface $passwordHasher,
    ) {
    }

    public function load(ObjectManager $manager): void
    {
        $faker = Factory::create('ru_RU');
        $slugger = new AsciiSlugger('ru');

        // --- Users ---
        $users = [];

        $admin = new User();
        $admin->setEmail('admin@example.com');
        $admin->setName('Администратор');
        $admin->setRoles(['ROLE_ADMIN']);
        $admin->setPassword($this->passwordHasher->hashPassword($admin, 'password'));
        $manager->persist($admin);
        $users[] = $admin;

        for ($i = 1; $i <= 4; ++$i) {
            $user = new User();
            $user->setEmail($faker->unique()->safeEmail());
            $user->setName($faker->name());
            $user->setRoles(['ROLE_USER']);
            $user->setPassword($this->passwordHasher->hashPassword($user, 'password'));
            $manager->persist($user);
            $users[] = $user;
        }

        // --- Categories ---
        $categories = [];
        $categoryNames = ['Новости', 'Статьи', 'Обзоры', 'Разное', 'Технологии'];

        foreach ($categoryNames as $name) {
            $category = new Category();
            $category->setName($name);
            $category->setSlug((string) $slugger->slug($name)->lower());
            $manager->persist($category);
            $categories[] = $category;
        }

        // --- Posts ---
        for ($i = 1; $i <= 30; ++$i) {
            $title = $faker->sentence(random_int(3, 7));
            $title = rtrim($title, '.');

            $post = new Post();
            $post->setTitle($title);
            $post->setSlug((string) $slugger->slug($title.'-'.$i)->lower());
            $post->setContent(implode("\n\n", $faker->paragraphs(random_int(2, 5))));
            $post->setCategory($categories[array_rand($categories)]);
            $post->setAuthor($users[array_rand($users)]);
            $post->setPublished((bool) random_int(0, 1));
            $post->setCreatedAt(
                \DateTimeImmutable::createFromMutable($faker->dateTimeBetween('-1 year', 'now')),
            );
            $manager->persist($post);
        }

        $manager->flush();
    }
}
