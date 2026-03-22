import SpriteKit
import GameplayKit

// MARK: - Physics Categories
struct PhysicsCategory {
    static let none:      UInt32 = 0
    static let player:    UInt32 = 0b0001
    static let invader:   UInt32 = 0b0010
    static let bullet:    UInt32 = 0b0100
    static let bomb:      UInt32 = 0b1000
    static let barrier:   UInt32 = 0b10000
}

// MARK: - Game Constants
struct GameConstants {
    static let playerSpeed: CGFloat = 250
    static let bulletSpeed: CGFloat = 500
    static let bombSpeed: CGFloat = 200
    static let invaderRows = 4
    static let invaderCols = 9
    static let invaderMoveInterval: TimeInterval = 0.6
    static let invaderDropAmount: CGFloat = 20
    static let bombDropInterval: TimeInterval = 1.5
    static let barrierCount = 4
}

// MARK: - Game State
enum GameState {
    case menu, playing, paused, gameOver, victory
}

class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Properties
    var gameState: GameState = .menu
    var score = 0
    var lives = 3
    var level = 1
    var invaderMoveInterval: TimeInterval = GameConstants.invaderMoveInterval

    // Nodes
    var player: SKSpriteNode!
    var invaders: [SKSpriteNode] = []
    var bullets: [SKSpriteNode] = []
    var bombs: [SKSpriteNode] = []
    var barriers: [SKNode] = []

    // Labels
    var scoreLabel: SKLabelNode!
    var livesLabel: SKLabelNode!
    var levelLabel: SKLabelNode!
    var messageLabel: SKLabelNode!
    var subMessageLabel: SKLabelNode!

    // Control
    var leftButton: SKShapeNode!
    var rightButton: SKShapeNode!
    var fireButton: SKShapeNode!

    // State
    var invaderDirection: CGFloat = 1.0
    var invaderMoveTimer: TimeInterval = 0
    var bombTimer: TimeInterval = 0
    var touchLeft = false
    var touchRight = false
    var canFire = true
    var fireCooldown: TimeInterval = 0.35
    var fireCooldownTimer: TimeInterval = 0
    var lastUpdateTime: TimeInterval = 0
    var mysteryShip: SKSpriteNode?
    var mysteryTimer: TimeInterval = 0
    var mysteryInterval: TimeInterval = 15

    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupPhysics()
        showMenu()
    }

    func setupPhysics() {
        physicsWorld.gravity = CGVector(dx: 0, dy: 0)
        physicsWorld.contactDelegate = self
    }

    // MARK: - Menu
    func showMenu() {
        gameState = .menu
        removeAllChildren()

        // Stars background
        addStarfield()

        // Title
        let title = SKLabelNode(fontNamed: "Courier-Bold")
        title.text = "SPACE INVADERS"
        title.fontSize = 36
        title.fontColor = .green
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        addChild(title)

        // Pulsing animation
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 0.6),
            SKAction.scale(to: 0.95, duration: 0.6)
        ])
        title.run(SKAction.repeatForever(pulse))

        // Demo invaders
        let invaderTypes = ["👾", "👽", "🛸", "😈"]
        let descriptions = ["= 10 PTS", "= 20 PTS", "= 30 PTS", "= MYSTERY"]
        for (i, emoji) in invaderTypes.enumerated() {
            let emojiLabel = SKLabelNode(fontNamed: "Helvetica")
            emojiLabel.text = emoji
            emojiLabel.fontSize = 28
            emojiLabel.position = CGPoint(x: size.width * 0.3, y: size.height * 0.55 - CGFloat(i) * 42)
            addChild(emojiLabel)

            let desc = SKLabelNode(fontNamed: "Courier")
            desc.text = descriptions[i]
            desc.fontSize = 18
            desc.fontColor = .white
            desc.position = CGPoint(x: size.width * 0.58, y: size.height * 0.55 - CGFloat(i) * 42 - 5)
            desc.horizontalAlignmentMode = .left
            addChild(desc)
        }

        // Play button
        let playButton = SKShapeNode(rectOf: CGSize(width: 200, height: 55), cornerRadius: 12)
        playButton.fillColor = SKColor(red: 0, green: 0.7, blue: 0, alpha: 1)
        playButton.strokeColor = .green
        playButton.lineWidth = 2
        playButton.position = CGPoint(x: size.width / 2, y: size.height * 0.22)
        playButton.name = "playButton"
        addChild(playButton)

        let playLabel = SKLabelNode(fontNamed: "Courier-Bold")
        playLabel.text = "TAP TO PLAY"
        playLabel.fontSize = 22
        playLabel.fontColor = .white
        playLabel.verticalAlignmentMode = .center
        playLabel.name = "playButton"
        playButton.addChild(playLabel)

        let buttonPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        playButton.run(SKAction.repeatForever(buttonPulse))

        // High score hint
        let hint = SKLabelNode(fontNamed: "Courier")
        hint.text = "© 2024 SPACE INVADERS"
        hint.fontSize = 13
        hint.fontColor = SKColor(white: 0.5, alpha: 1)
        hint.position = CGPoint(x: size.width / 2, y: 25)
        addChild(hint)
    }

    // MARK: - Start Game
    func startGame() {
        score = 0
        lives = 3
        level = 1
        invaderMoveInterval = GameConstants.invaderMoveInterval
        setupGame()
    }

    func setupGame() {
        gameState = .playing
        removeAllChildren()
        invaders.removeAll()
        bullets.removeAll()
        bombs.removeAll()
        barriers.removeAll()
        mysteryShip = nil

        backgroundColor = .black
        addStarfield()
        setupHUD()
        setupPlayer()
        setupInvaders()
        setupBarriers()
        setupControls()
    }

    func nextLevel() {
        level += 1
        invaderMoveInterval = max(0.15, GameConstants.invaderMoveInterval - Double(level - 1) * 0.08)
        bombs.removeAll()
        bullets.removeAll()
        mysteryShip = nil

        // Show level message briefly
        let lvlMsg = SKLabelNode(fontNamed: "Courier-Bold")
        lvlMsg.text = "LEVEL \(level)"
        lvlMsg.fontSize = 40
        lvlMsg.fontColor = .yellow
        lvlMsg.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(lvlMsg)

        let appear = SKAction.sequence([
            SKAction.wait(forDuration: 1.5),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ])
        lvlMsg.run(appear) { [weak self] in
            self?.setupInvaders()
            self?.setupBarriers()
        }
    }

    // MARK: - HUD
    func setupHUD() {
        // Background bar
        let hudBg = SKShapeNode(rectOf: CGSize(width: size.width, height: 44))
        hudBg.fillColor = SKColor(red: 0, green: 0.1, blue: 0, alpha: 0.8)
        hudBg.strokeColor = .green
        hudBg.lineWidth = 1
        hudBg.position = CGPoint(x: size.width / 2, y: size.height - 22)
        addChild(hudBg)

        scoreLabel = SKLabelNode(fontNamed: "Courier-Bold")
        scoreLabel.text = "SCORE: 0"
        scoreLabel.fontSize = 16
        scoreLabel.fontColor = .green
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 10, y: size.height - 30)
        addChild(scoreLabel)

        livesLabel = SKLabelNode(fontNamed: "Courier-Bold")
        livesLabel.fontSize = 16
        livesLabel.fontColor = .red
        livesLabel.horizontalAlignmentMode = .center
        livesLabel.position = CGPoint(x: size.width / 2, y: size.height - 30)
        addChild(livesLabel)
        updateLivesDisplay()

        levelLabel = SKLabelNode(fontNamed: "Courier-Bold")
        levelLabel.text = "LVL: \(level)"
        levelLabel.fontSize = 16
        levelLabel.fontColor = .cyan
        levelLabel.horizontalAlignmentMode = .right
        levelLabel.position = CGPoint(x: size.width - 10, y: size.height - 30)
        addChild(levelLabel)
    }

    func updateHUD() {
        scoreLabel.text = "SCORE: \(score)"
        levelLabel.text = "LVL: \(level)"
        updateLivesDisplay()
    }

    func updateLivesDisplay() {
        var display = "LIVES: "
        for _ in 0..<lives { display += "🚀" }
        livesLabel.text = display
    }

    // MARK: - Player
    func setupPlayer() {
        player = SKSpriteNode(color: .clear, size: CGSize(width: 44, height: 44))
        player.position = CGPoint(x: size.width / 2, y: 100)
        player.name = "player"

        // Draw player ship using shape
        let ship = makePlayerShip()
        player.addChild(ship)

        player.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 40, height: 20))
        player.physicsBody?.categoryBitMask = PhysicsCategory.player
        player.physicsBody?.contactTestBitMask = PhysicsCategory.bomb
        player.physicsBody?.collisionBitMask = PhysicsCategory.none
        player.physicsBody?.isDynamic = false
        addChild(player)
    }

    func makePlayerShip() -> SKNode {
        let ship = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 18))
        path.addLine(to: CGPoint(x: -20, y: -10))
        path.addLine(to: CGPoint(x: -8, y: -10))
        path.addLine(to: CGPoint(x: -8, y: -18))
        path.addLine(to: CGPoint(x: 8, y: -18))
        path.addLine(to: CGPoint(x: 8, y: -10))
        path.addLine(to: CGPoint(x: 20, y: -10))
        path.closeSubpath()
        ship.path = path
        ship.fillColor = .green
        ship.strokeColor = SKColor(red: 0, green: 0.6, blue: 0, alpha: 1)
        ship.lineWidth = 1
        return ship
    }

    // MARK: - Invaders
    func setupInvaders() {
        let startX = size.width * 0.12
        let startY = size.height * 0.78
        let spacingX = (size.width * 0.78) / CGFloat(GameConstants.invaderCols - 1)
        let spacingY: CGFloat = 48

        for row in 0..<GameConstants.invaderRows {
            for col in 0..<GameConstants.invaderCols {
                let invader = makeInvader(row: row)
                invader.position = CGPoint(
                    x: startX + CGFloat(col) * spacingX,
                    y: startY - CGFloat(row) * spacingY
                )
                invader.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 26))
                invader.physicsBody?.categoryBitMask = PhysicsCategory.invader
                invader.physicsBody?.contactTestBitMask = PhysicsCategory.bullet
                invader.physicsBody?.collisionBitMask = PhysicsCategory.none
                invader.physicsBody?.isDynamic = false
                addChild(invader)
                invaders.append(invader)
            }
        }
    }

    func makeInvader(row: Int) -> SKSpriteNode {
        let invader = SKSpriteNode(color: .clear, size: CGSize(width: 36, height: 30))
        invader.name = "invader_\(row)"

        let label = SKLabelNode(fontNamed: "Helvetica")
        label.fontSize = 28
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        let emojis: [String]
        switch row {
        case 0:  emojis = ["👾"]
        case 1:  emojis = ["👽"]
        case 2:  emojis = ["🛸"]
        default: emojis = ["😈"]
        }

        label.text = emojis[0]
        invader.addChild(label)

        // Animate between two states
        let anim = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.4),
            SKAction.scale(to: 0.9, duration: 0.4)
        ])
        label.run(SKAction.repeatForever(anim))

        return invader
    }

    // MARK: - Barriers
    func setupBarriers() {
        // Remove old barriers
        for b in barriers { b.removeFromParent() }
        barriers.removeAll()

        let spacing = size.width / CGFloat(GameConstants.barrierCount + 1)

        for i in 0..<GameConstants.barrierCount {
            let x = spacing * CGFloat(i + 1)
            let y: CGFloat = 175

            for bRow in 0..<3 {
                for bCol in 0..<6 {
                    let block = SKShapeNode(rectOf: CGSize(width: 9, height: 10))
                    block.fillColor = SKColor(red: 0, green: 0.8, blue: 0, alpha: 1)
                    block.strokeColor = .clear
                    block.position = CGPoint(
                        x: x - 30 + CGFloat(bCol) * 10 + 5,
                        y: y + CGFloat(bRow) * 11
                    )
                    block.name = "barrier"
                    block.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 9, height: 10))
                    block.physicsBody?.categoryBitMask = PhysicsCategory.barrier
                    block.physicsBody?.contactTestBitMask = PhysicsCategory.bullet | PhysicsCategory.bomb
                    block.physicsBody?.collisionBitMask = PhysicsCategory.none
                    block.physicsBody?.isDynamic = false
                    addChild(block)
                    barriers.append(block)
                }
            }
        }
    }

    // MARK: - Controls
    func setupControls() {
        let controlY: CGFloat = 50
        let buttonSize = CGSize(width: 80, height: 70)
        let cornerRadius: CGFloat = 14

        // Left button
        leftButton = SKShapeNode(rectOf: buttonSize, cornerRadius: cornerRadius)
        leftButton.fillColor = SKColor(white: 0.15, alpha: 0.9)
        leftButton.strokeColor = SKColor(white: 0.4, alpha: 1)
        leftButton.lineWidth = 1.5
        leftButton.position = CGPoint(x: 55, y: controlY)
        leftButton.name = "leftButton"
        leftButton.zPosition = 10
        addChild(leftButton)

        let leftArrow = SKLabelNode(fontNamed: "Helvetica-Bold")
        leftArrow.text = "◀"
        leftArrow.fontSize = 28
        leftArrow.fontColor = .white
        leftArrow.verticalAlignmentMode = .center
        leftArrow.name = "leftButton"
        leftButton.addChild(leftArrow)

        // Right button
        rightButton = SKShapeNode(rectOf: buttonSize, cornerRadius: cornerRadius)
        rightButton.fillColor = SKColor(white: 0.15, alpha: 0.9)
        rightButton.strokeColor = SKColor(white: 0.4, alpha: 1)
        rightButton.lineWidth = 1.5
        rightButton.position = CGPoint(x: 145, y: controlY)
        rightButton.name = "rightButton"
        rightButton.zPosition = 10
        addChild(rightButton)

        let rightArrow = SKLabelNode(fontNamed: "Helvetica-Bold")
        rightArrow.text = "▶"
        rightArrow.fontSize = 28
        rightArrow.fontColor = .white
        rightArrow.verticalAlignmentMode = .center
        rightArrow.name = "rightButton"
        rightButton.addChild(rightArrow)

        // Fire button
        fireButton = SKShapeNode(circleOfRadius: 36)
        fireButton.fillColor = SKColor(red: 0.7, green: 0, blue: 0, alpha: 0.9)
        fireButton.strokeColor = .red
        fireButton.lineWidth = 2
        fireButton.position = CGPoint(x: size.width - 55, y: controlY)
        fireButton.name = "fireButton"
        fireButton.zPosition = 10
        addChild(fireButton)

        let fireLabel = SKLabelNode(fontNamed: "Courier-Bold")
        fireLabel.text = "FIRE"
        fireLabel.fontSize = 14
        fireLabel.fontColor = .white
        fireLabel.verticalAlignmentMode = .center
        fireLabel.name = "fireButton"
        fireButton.addChild(fireLabel)
    }

    // MARK: - Shooting
    func fireBullet() {
        guard canFire else { return }
        canFire = false
        fireCooldownTimer = 0

        let bullet = SKShapeNode(rectOf: CGSize(width: 4, height: 14), cornerRadius: 2)
        bullet.fillColor = .yellow
        bullet.strokeColor = .orange
        bullet.lineWidth = 1
        bullet.position = CGPoint(x: player.position.x, y: player.position.y + 24)
        bullet.name = "bullet"
        bullet.zPosition = 5

        let bulletSprite = SKSpriteNode(color: .clear, size: CGSize(width: 4, height: 14))
        bulletSprite.position = bullet.position
        bulletSprite.name = "bullet"
        bulletSprite.zPosition = 5

        bulletSprite.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 4, height: 14))
        bulletSprite.physicsBody?.categoryBitMask = PhysicsCategory.bullet
        bulletSprite.physicsBody?.contactTestBitMask = PhysicsCategory.invader | PhysicsCategory.barrier
        bulletSprite.physicsBody?.collisionBitMask = PhysicsCategory.none
        bulletSprite.physicsBody?.isDynamic = true
        bulletSprite.physicsBody?.affectedByGravity = false

        addChild(bullet)
        addChild(bulletSprite)
        bullets.append(bulletSprite)

        let move = SKAction.moveBy(x: 0, y: size.height, duration: TimeInterval(size.height / GameConstants.bulletSpeed))
        let remove = SKAction.run { [weak self, weak bulletSprite, weak bullet] in
            bullet?.removeFromParent()
            if let bs = bulletSprite {
                self?.bullets.removeAll { $0 === bs }
                bs.removeFromParent()
            }
        }
        bullet.run(SKAction.sequence([move, remove]))
        bulletSprite.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: size.height, duration: TimeInterval(size.height / GameConstants.bulletSpeed)),
            SKAction.removeFromParent()
        ]))

        // Muzzle flash
        let flash = SKShapeNode(circleOfRadius: 6)
        flash.fillColor = .yellow
        flash.strokeColor = .clear
        flash.position = CGPoint(x: player.position.x, y: player.position.y + 24)
        flash.zPosition = 6
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.08),
            SKAction.removeFromParent()
        ]))
    }

    func dropBomb() {
        let aliveInvaders = invaders.filter { $0.parent != nil }
        guard !aliveInvaders.isEmpty else { return }

        // Pick a random invader from the bottom row of each column
        let randomInvader = aliveInvaders.randomElement()!

        let bomb = SKShapeNode(rectOf: CGSize(width: 5, height: 12), cornerRadius: 2)
        bomb.fillColor = .orange
        bomb.strokeColor = .red
        bomb.lineWidth = 1
        bomb.position = CGPoint(x: randomInvader.position.x, y: randomInvader.position.y - 20)
        bomb.name = "bombShape"
        bomb.zPosition = 5

        let bombSprite = SKSpriteNode(color: .clear, size: CGSize(width: 5, height: 12))
        bombSprite.position = bomb.position
        bombSprite.name = "bomb"
        bombSprite.zPosition = 5

        bombSprite.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 5, height: 12))
        bombSprite.physicsBody?.categoryBitMask = PhysicsCategory.bomb
        bombSprite.physicsBody?.contactTestBitMask = PhysicsCategory.player | PhysicsCategory.barrier
        bombSprite.physicsBody?.collisionBitMask = PhysicsCategory.none
        bombSprite.physicsBody?.isDynamic = true
        bombSprite.physicsBody?.affectedByGravity = false

        addChild(bomb)
        addChild(bombSprite)
        bombs.append(bombSprite)

        let duration = TimeInterval((bombSprite.position.y) / GameConstants.bombSpeed)
        let moveShape = SKAction.moveBy(x: 0, y: -bombSprite.position.y - 20, duration: duration)
        let moveSprite = SKAction.moveBy(x: 0, y: -bombSprite.position.y - 20, duration: duration)

        let removeBoth = SKAction.run { [weak self, weak bombSprite, weak bomb] in
            bomb?.removeFromParent()
            if let bs = bombSprite {
                self?.bombs.removeAll { $0 === bs }
                bs.removeFromParent()
            }
        }

        bomb.run(SKAction.sequence([moveShape, SKAction.removeFromParent()]))
        bombSprite.run(SKAction.sequence([moveSprite, removeBoth]))
    }

    // MARK: - Mystery Ship
    func spawnMysteryShip() {
        guard mysteryShip == nil || mysteryShip?.parent == nil else { return }

        let mystery = SKSpriteNode(color: .clear, size: CGSize(width: 44, height: 22))
        mystery.name = "mystery"
        mystery.position = CGPoint(x: -30, y: size.height - 75)

        let label = SKLabelNode(fontNamed: "Helvetica")
        label.text = "🚀"
        label.fontSize = 26
        label.verticalAlignmentMode = .center
        mystery.addChild(label)

        mystery.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 44, height: 22))
        mystery.physicsBody?.categoryBitMask = PhysicsCategory.invader
        mystery.physicsBody?.contactTestBitMask = PhysicsCategory.bullet
        mystery.physicsBody?.collisionBitMask = PhysicsCategory.none
        mystery.physicsBody?.isDynamic = false

        addChild(mystery)
        mysteryShip = mystery

        let move = SKAction.moveTo(x: size.width + 30, duration: 5)
        let remove = SKAction.removeFromParent()
        mystery.run(SKAction.sequence([move, remove]))
    }

    // MARK: - Invader Movement
    func moveInvaders() {
        let aliveInvaders = invaders.filter { $0.parent != nil }
        guard !aliveInvaders.isEmpty else { return }

        var hitEdge = false
        for invader in aliveInvaders {
            let newX = invader.position.x + (invaderDirection * 16)
            if newX <= 20 || newX >= size.width - 20 {
                hitEdge = true
                break
            }
        }

        if hitEdge {
            invaderDirection *= -1
            for invader in aliveInvaders {
                invader.position.y -= GameConstants.invaderDropAmount
            }
            // Check if invaders reached the player
            for invader in aliveInvaders {
                if invader.position.y <= 145 {
                    gameOver()
                    return
                }
            }
        } else {
            for invader in aliveInvaders {
                invader.position.x += invaderDirection * 16
            }
        }

        // Speed up as fewer invaders remain
        let ratio = Double(aliveInvaders.count) / Double(GameConstants.invaderRows * GameConstants.invaderCols)
        invaderMoveTimer = invaderMoveInterval * max(0.2, ratio)
    }

    // MARK: - Collisions
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB

        let maskA = bodyA.categoryBitMask
        let maskB = bodyB.categoryBitMask

        if (maskA == PhysicsCategory.bullet && maskB == PhysicsCategory.invader) ||
           (maskA == PhysicsCategory.invader && maskB == PhysicsCategory.bullet) {
            let bulletNode = maskA == PhysicsCategory.bullet ? bodyA.node : bodyB.node
            let invaderNode = maskA == PhysicsCategory.invader ? bodyA.node : bodyB.node
            bulletHitInvader(bullet: bulletNode, invader: invaderNode)
        }

        if (maskA == PhysicsCategory.bomb && maskB == PhysicsCategory.player) ||
           (maskA == PhysicsCategory.player && maskB == PhysicsCategory.bomb) {
            let bombNode = maskA == PhysicsCategory.bomb ? bodyA.node : bodyB.node
            bombHitPlayer(bomb: bombNode)
        }

        if (maskA == PhysicsCategory.bullet && maskB == PhysicsCategory.barrier) ||
           (maskA == PhysicsCategory.barrier && maskB == PhysicsCategory.bullet) {
            let bulletNode = maskA == PhysicsCategory.bullet ? bodyA.node : bodyB.node
            let barrierNode = maskA == PhysicsCategory.barrier ? bodyA.node : bodyB.node
            bulletHitBarrier(bullet: bulletNode, barrier: barrierNode)
        }

        if (maskA == PhysicsCategory.bomb && maskB == PhysicsCategory.barrier) ||
           (maskA == PhysicsCategory.barrier && maskB == PhysicsCategory.bomb) {
            let bombNode = maskA == PhysicsCategory.bomb ? bodyA.node : bodyB.node
            let barrierNode = maskA == PhysicsCategory.barrier ? bodyA.node : bodyB.node
            bombHitBarrier(bomb: bombNode, barrier: barrierNode)
        }
    }

    func bulletHitInvader(bullet: SKNode?, invader: SKNode?) {
        guard let bullet = bullet, let invader = invader else { return }
        guard bullet.parent != nil && invader.parent != nil else { return }

        // Calculate score based on invader type
        var points = 10
        if let name = invader.name {
            if name.contains("mystery") || invader.name == "mystery" {
                points = Int.random(in: 1...6) * 50
            } else if name.contains("_0") { points = 10 }
            else if name.contains("_1") { points = 20 }
            else if name.contains("_2") { points = 30 }
            else if name.contains("_3") { points = 40 }
        }

        // Check if it's the mystery ship
        if invader.name == "mystery" { points = Int.random(in: 1...6) * 50 }

        score += points
        updateHUD()

        // Explosion
        showExplosion(at: invader.position, points: points)

        bullet.removeFromParent()
        bullets.removeAll { $0 === bullet }
        invader.removeFromParent()
        invaders.removeAll { $0 === invader }

        // Check win condition
        let aliveInvaders = invaders.filter { $0.parent != nil }
        if aliveInvaders.isEmpty {
            victory()
        }
    }

    func bombHitPlayer(bomb: SKNode?) {
        guard let bomb = bomb else { return }
        guard bomb.parent != nil else { return }

        bomb.removeFromParent()
        bombs.removeAll { $0 === bomb }

        lives -= 1
        updateHUD()
        showExplosion(at: player.position, points: 0)

        if lives <= 0 {
            gameOver()
        } else {
            // Flash player
            let flash = SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.fadeIn(withDuration: 0.1)
            ])
            player.run(SKAction.repeat(flash, count: 6))
        }
    }

    func bulletHitBarrier(bullet: SKNode?, barrier: SKNode?) {
        guard let bullet = bullet, let barrier = barrier else { return }
        bullet.removeFromParent()
        bullets.removeAll { $0 === bullet }
        barrier.removeFromParent()
        barriers.removeAll { $0 === barrier }
    }

    func bombHitBarrier(bomb: SKNode?, barrier: SKNode?) {
        guard let bomb = bomb, let barrier = barrier else { return }
        bomb.removeFromParent()
        bombs.removeAll { $0 === bomb }
        barrier.removeFromParent()
        barriers.removeAll { $0 === barrier }
    }

    // MARK: - Effects
    func showExplosion(at position: CGPoint, points: Int) {
        // Particle burst using shapes
        for _ in 0..<8 {
            let particle = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...6))
            particle.fillColor = [SKColor.red, .orange, .yellow, .white].randomElement()!
            particle.strokeColor = .clear
            particle.position = position
            particle.zPosition = 8
            addChild(particle)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 20...50)
            let dx = cos(angle) * distance
            let dy = sin(angle) * distance

            particle.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 0.4),
                    SKAction.fadeOut(withDuration: 0.4),
                    SKAction.scale(to: 0.1, duration: 0.4)
                ]),
                SKAction.removeFromParent()
            ]))
        }

        // Points popup
        if points > 0 {
            let pointsLabel = SKLabelNode(fontNamed: "Courier-Bold")
            pointsLabel.text = "+\(points)"
            pointsLabel.fontSize = 16
            pointsLabel.fontColor = points >= 100 ? .yellow : .white
            pointsLabel.position = position
            pointsLabel.zPosition = 9
            addChild(pointsLabel)

            pointsLabel.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: 0, y: 30, duration: 0.6),
                    SKAction.fadeOut(withDuration: 0.6)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: - Starfield
    func addStarfield() {
        for _ in 0..<80 {
            let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.5...1.5))
            star.fillColor = SKColor(white: CGFloat.random(in: 0.5...1.0), alpha: 1)
            star.strokeColor = .clear
            star.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            star.zPosition = -1
            addChild(star)

            // Twinkling
            let twinkle = SKAction.sequence([
                SKAction.fadeAlpha(to: CGFloat.random(in: 0.2...0.5), duration: CGFloat.random(in: 0.5...2.0)),
                SKAction.fadeAlpha(to: 1.0, duration: CGFloat.random(in: 0.5...2.0))
            ])
            star.run(SKAction.repeatForever(twinkle))
        }
    }

    // MARK: - Game Over / Victory
    func gameOver() {
        gameState = .gameOver
        // Stop all bombs and bullets
        for bomb in bombs { bomb.removeFromParent() }
        for bullet in bullets { bullet.removeFromParent() }

        let overlay = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        overlay.fillColor = SKColor(red: 0.5, green: 0, blue: 0, alpha: 0.6)
        overlay.strokeColor = .clear
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 20
        addChild(overlay)

        let goLabel = SKLabelNode(fontNamed: "Courier-Bold")
        goLabel.text = "GAME OVER"
        goLabel.fontSize = 44
        goLabel.fontColor = .red
        goLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 50)
        goLabel.zPosition = 21
        addChild(goLabel)

        let scoreEnd = SKLabelNode(fontNamed: "Courier-Bold")
        scoreEnd.text = "SCORE: \(score)"
        scoreEnd.fontSize = 24
        scoreEnd.fontColor = .white
        scoreEnd.position = CGPoint(x: size.width / 2, y: size.height / 2)
        scoreEnd.zPosition = 21
        addChild(scoreEnd)

        let restart = SKLabelNode(fontNamed: "Courier-Bold")
        restart.text = "TAP TO RESTART"
        restart.fontSize = 20
        restart.fontColor = .yellow
        restart.position = CGPoint(x: size.width / 2, y: size.height / 2 - 60)
        restart.name = "restart"
        restart.zPosition = 21
        addChild(restart)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        restart.run(SKAction.repeatForever(pulse))
    }

    func victory() {
        gameState = .victory

        let overlay = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        overlay.fillColor = SKColor(red: 0, green: 0.3, blue: 0, alpha: 0.6)
        overlay.strokeColor = .clear
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 20
        addChild(overlay)

        let winLabel = SKLabelNode(fontNamed: "Courier-Bold")
        winLabel.text = "YOU WIN!"
        winLabel.fontSize = 44
        winLabel.fontColor = .green
        winLabel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
        winLabel.zPosition = 21
        addChild(winLabel)

        let scoreEnd = SKLabelNode(fontNamed: "Courier-Bold")
        scoreEnd.text = "SCORE: \(score)"
        scoreEnd.fontSize = 24
        scoreEnd.fontColor = .white
        scoreEnd.position = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
        scoreEnd.zPosition = 21
        addChild(scoreEnd)

        let nextBtn = SKLabelNode(fontNamed: "Courier-Bold")
        nextBtn.text = "NEXT LEVEL ▶"
        nextBtn.fontSize = 22
        nextBtn.fontColor = .yellow
        nextBtn.position = CGPoint(x: size.width / 2, y: size.height / 2 - 50)
        nextBtn.name = "nextLevel"
        nextBtn.zPosition = 21
        addChild(nextBtn)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        nextBtn.run(SKAction.repeatForever(pulse))
    }

    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let nodes = self.nodes(at: location)

        if gameState == .menu {
            if nodes.contains(where: { $0.name == "playButton" }) {
                startGame()
            } else {
                startGame()
            }
            return
        }

        if gameState == .gameOver {
            startGame()
            return
        }

        if gameState == .victory {
            if nodes.contains(where: { $0.name == "nextLevel" }) {
                gameState = .playing
                // Remove overlay nodes
                children.filter { $0.zPosition >= 20 }.forEach { $0.removeFromParent() }
                nextLevel()
            }
            return
        }

        if gameState == .playing {
            for node in nodes {
                if node.name == "leftButton" { touchLeft = true }
                if node.name == "rightButton" { touchRight = true }
                if node.name == "fireButton" { fireBullet() }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let nodes = self.nodes(at: location)

        var endedLeft = false
        var endedRight = false
        for node in nodes {
            if node.name == "leftButton" { endedLeft = true }
            if node.name == "rightButton" { endedRight = true }
        }

        if endedLeft { touchLeft = false }
        if endedRight { touchRight = false }

        // If touch ended outside button area, release both
        if !endedLeft && !endedRight {
            touchLeft = false
            touchRight = false
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLeft = false
        touchRight = false
    }

    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        guard gameState == .playing else { return }

        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        // Move player
        if touchLeft {
            let newX = max(24, player.position.x - GameConstants.playerSpeed * CGFloat(dt))
            player.position.x = newX
        }
        if touchRight {
            let newX = min(size.width - 24, player.position.x + GameConstants.playerSpeed * CGFloat(dt))
            player.position.x = newX
        }

        // Fire cooldown
        if !canFire {
            fireCooldownTimer += dt
            if fireCooldownTimer >= fireCooldown {
                canFire = true
                fireCooldownTimer = 0
            }
        }

        // Invader movement
        invaderMoveTimer += dt
        let currentInterval = max(0.12, invaderMoveInterval * max(0.2, Double(invaders.filter { $0.parent != nil }.count) / Double(GameConstants.invaderRows * GameConstants.invaderCols)))
        if invaderMoveTimer >= currentInterval {
            invaderMoveTimer = 0
            moveInvaders()
        }

        // Bomb dropping
        bombTimer += dt
        let currentBombInterval = max(0.5, GameConstants.bombDropInterval - Double(level - 1) * 0.1)
        if bombTimer >= currentBombInterval {
            bombTimer = 0
            dropBomb()
        }

        // Mystery ship
        mysteryTimer += dt
        if mysteryTimer >= mysteryInterval {
            mysteryTimer = 0
            spawnMysteryShip()
        }
    }
}
