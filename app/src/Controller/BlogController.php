<?php

declare(strict_types=1);

namespace App\Controller;

use App\Repository\CategoryRepository;
use App\Repository\PostRepository;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

class BlogController extends AbstractController
{
    #[Route('/', name: 'blog_index')]
    public function index(PostRepository $posts): Response
    {
        return $this->render('blog/index.html.twig', [
            'posts' => $posts->findPublishedOrdered(),
        ]);
    }

    #[Route('/category/{slug}', name: 'blog_category')]
    public function category(CategoryRepository $categories, string $slug): Response
    {
        $category = $categories->findOneBy(['slug' => $slug]);

        if (!$category) {
            throw $this->createNotFoundException();
        }

        return $this->render('blog/category.html.twig', [
            'category' => $category,
            'posts' => $category->getPosts(),
        ]);
    }

    #[Route('/post/{slug}', name: 'blog_show')]
    public function show(PostRepository $posts, string $slug): Response
    {
        $post = $posts->findOneBy(['slug' => $slug, 'published' => true]);

        if (!$post) {
            throw $this->createNotFoundException();
        }

        return $this->render('blog/show.html.twig', [
            'post' => $post,
        ]);
    }
}
