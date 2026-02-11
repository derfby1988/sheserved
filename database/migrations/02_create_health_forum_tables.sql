-- =====================================================
-- Health Forum / Articles Feature Schema
-- =====================================================

-- 1. ARTICLES TABLE
CREATE TABLE IF NOT EXISTS health_articles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    view_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    bookmark_count INTEGER DEFAULT 0,
    category VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for articles
CREATE INDEX IF NOT EXISTS idx_health_articles_author_id ON health_articles(author_id);
CREATE INDEX IF NOT EXISTS idx_health_articles_category ON health_articles(category);
CREATE INDEX IF NOT EXISTS idx_health_articles_created_at ON health_articles(created_at DESC);

-- 2. COMMENTS TABLE (Nested)
CREATE TABLE IF NOT EXISTS health_article_comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES health_articles(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES health_article_comments(id) ON DELETE CASCADE, -- For replies
    content TEXT NOT NULL,
    comment_number INTEGER NOT NULL, -- Logical order within article
    view_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    bookmark_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for comments
CREATE INDEX IF NOT EXISTS idx_health_comments_article_id ON health_article_comments(article_id);
CREATE INDEX IF NOT EXISTS idx_health_comments_user_id ON health_article_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_health_comments_parent_id ON health_article_comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_health_comments_created_at ON health_article_comments(created_at DESC);

-- 3. PRODUCTS TAGGED IN ARTICLES
CREATE TABLE IF NOT EXISTS health_article_products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES health_articles(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    url TEXT,
    tag_type VARCHAR(20) CHECK (tag_type IN ('author', 'sponsor', 'user')),
    tagged_by_id UUID REFERENCES users(id) ON DELETE SET NULL,
    is_approved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for products
CREATE INDEX IF NOT EXISTS idx_health_products_article_id ON health_article_products(article_id);
CREATE INDEX IF NOT EXISTS idx_health_products_tag_type ON health_article_products(tag_type);

-- 4. INTERACTIONS (Likes, Bookmarks, Shares)
CREATE TABLE IF NOT EXISTS health_article_interactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES health_articles(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES health_article_comments(id) ON DELETE CASCADE, -- Optional (if comment interaction)
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL CHECK (type IN ('like', 'bookmark', 'share')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, article_id, comment_id, type)
);

-- Index for interactions
CREATE INDEX IF NOT EXISTS idx_health_interactions_user_article ON health_article_interactions(user_id, article_id);
CREATE INDEX IF NOT EXISTS idx_health_interactions_article_id ON health_article_interactions(article_id);
CREATE INDEX IF NOT EXISTS idx_health_interactions_comment_id ON health_article_interactions(comment_id);

-- 5. NOTIFICATIONS
CREATE TABLE IF NOT EXISTS health_notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
    article_id UUID REFERENCES health_articles(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL CHECK (type IN ('comment', 'reply', 'tag_product')),
    message TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for notifications
CREATE INDEX IF NOT EXISTS idx_health_notifications_recipient ON health_notifications(recipient_id, is_read);
CREATE INDEX IF NOT EXISTS idx_health_notifications_created_at ON health_notifications(created_at DESC);

-- =====================================================
-- TRIGGERS - Auto update updated_at
-- =====================================================

DROP TRIGGER IF EXISTS update_health_articles_updated_at ON health_articles;
CREATE TRIGGER update_health_articles_updated_at
    BEFORE UPDATE ON health_articles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_health_article_comments_updated_at ON health_article_comments;
CREATE TRIGGER update_health_article_comments_updated_at
    BEFORE UPDATE ON health_article_comments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
