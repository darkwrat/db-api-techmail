CREATE TABLE `user` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `email` varchar(255) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `username` varchar(255) DEFAULT NULL,
  `about` text,
  `isAnonymous` tinyint(1) NOT NULL DEFAULT '0',
  `temp` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_email_uindex` (`email`)
) ENGINE=InnoDB;

CREATE TABLE `forum` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `short_name` varchar(255) NOT NULL,
  `user_id` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `forum_short_name_uindex` (`short_name`),
  KEY `forum_user_id_fk` (`user_id`),
  CONSTRAINT `forum_user_id_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `thread` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `forum_id` int(11) NOT NULL,
  `isDeleted` tinyint(1) NOT NULL,
  `user_id` int(11) NOT NULL,
  `title` varchar(255) NOT NULL,
  `isClosed` tinyint(1) NOT NULL,
  `date` datetime NOT NULL,
  `message` text NOT NULL,
  `slug` varchar(255) NOT NULL,
  `likes` int(11) NOT NULL DEFAULT '0',
  `dislikes` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `thread_user_id_fk` (`user_id`),
  KEY `thread_forum_id_fk` (`forum_id`),
  CONSTRAINT `thread_forum_id_fk` FOREIGN KEY (`forum_id`) REFERENCES `forum` (`id`),
  CONSTRAINT `thread_user_id_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `post` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `parent_post_id` int(11) DEFAULT NULL,
  `isApproved` tinyint(1) NOT NULL,
  `isHighlighted` tinyint(1) NOT NULL,
  `isEdited` tinyint(1) NOT NULL,
  `isDeleted` tinyint(1) NOT NULL,
  `date` datetime NOT NULL,
  `thread_id` int(11) NOT NULL,
  `message` text NOT NULL,
  `user_id` int(11) NOT NULL,
  `forum_id` int(11) NOT NULL,
  `likes` int(11) NOT NULL DEFAULT '0',
  `dislikes` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `post_user_id_fk` (`user_id`),
  KEY `post_forum_id_fk` (`forum_id`),
  KEY `post_thread_id_fk` (`thread_id`),
  KEY `post_post_id_fk` (`parent_post_id`),
  CONSTRAINT `post_forum_id_fk` FOREIGN KEY (`forum_id`) REFERENCES `forum` (`id`),
  CONSTRAINT `post_post_id_fk` FOREIGN KEY (`parent_post_id`) REFERENCES `post` (`id`),
  CONSTRAINT `post_thread_id_fk` FOREIGN KEY (`thread_id`) REFERENCES `thread` (`id`),
  CONSTRAINT `post_user_id_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `userfollow` (
  `follower_user_id` int(11) NOT NULL DEFAULT '0',
  `followed_user_id` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`follower_user_id`,`followed_user_id`),
  KEY `userfollows_user2_id_fk` (`followed_user_id`),
  CONSTRAINT `userfollows_user2_id_fk` FOREIGN KEY (`followed_user_id`) REFERENCES `user` (`id`),
  CONSTRAINT `userfollows_user_id_fk` FOREIGN KEY (`follower_user_id`) REFERENCES `user` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `usersubscription` (
  `user_id` int(11) NOT NULL,
  `thread_id` int(11) NOT NULL,
  PRIMARY KEY (`user_id`,`thread_id`),
  KEY `usersubscriptions_thread_id_fk` (`thread_id`),
  CONSTRAINT `usersubscriptions_thread_id_fk` FOREIGN KEY (`thread_id`) REFERENCES `thread` (`id`),
  CONSTRAINT `usersubscriptions_user_id_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)
) ENGINE=InnoDB;
