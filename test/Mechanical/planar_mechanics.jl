using ModelingToolkit, OrdinaryDiffEq, Test
using ModelingToolkitStandardLibrary.Mechanical.PlanarMechanics
# using Plots

@parameters t
D = Differential(t)
tspan = (0.0, 3.0)
g = -9.807

@testset "Free body" begin
    m = 2
    j = 1
    @named body = Body(; m, j)
    @named model = ODESystem(Equation[],
        t,
        [],
        [],
        systems = [body])
    sys = structural_simplify(model)
    unset_vars = setdiff(states(sys), keys(ModelingToolkit.defaults(sys)))
    prob = ODEProblem(sys, unset_vars .=> 0.0, tspan, []; jac = true)

    sol = solve(prob, Rodas5P())
    @test SciMLBase.successful_retcode(sol)

    free_falling_displacement = 0.5 * g * tspan[end]^2  # 0.5 * g * t^2
    @test sol[body.ry][end] ≈ free_falling_displacement
    @test sol[body.rx][end] == 0  # no horizontal displacement
    @test all(sol[body.phi] .== 0)
    # plot(sol, idxs = [body.rx, body.ry])
end

@testset "Pendulum" begin
    @named ceiling = Fixed()
    @named rod = FixedTranslation(rx = 1.0, ry = 0.0)
    @named body = Body(m = 1, j = 0.1)
    @named revolute = Revolute(phi = 0.0, ω = 0.0)

    connections = [
        connect(ceiling.frame, revolute.frame_a),
        connect(revolute.frame_b, rod.frame_a),
        connect(rod.frame_b, body.frame),
    ]

    @named model = ODESystem(connections,
        t,
        [],
        [],
        systems = [body, revolute, rod, ceiling])
    sys = structural_simplify(model)
    unset_vars = setdiff(states(sys), keys(ModelingToolkit.defaults(sys)))
    prob = ODEProblem(sys, unset_vars .=> 0.0, tspan, []; jac = true)
    sol = solve(prob, Rodas5P())

    # phi and omega for the pendulum body
    @test length(states(sys)) == 2
end

@testset "Prismatic" begin
    r = [1.0, 0.0]
    e = r / sqrt(r' * r)
    @named prismatic = Prismatic(rx = r[1], ry = r[2], ex = e[1], ey = e[2])
    # just testing instantiation
    @test true
end

@testset "Position Sensors (two free falling bodies)" begin
    m = 1
    j = 1
    resolve_in_frame = :world

    @named body1 = Body(; m, j)
    @named body2 = Body(; m, j)
    @named base = Fixed()

    @named abs_pos_sensor = AbsolutePosition(; resolve_in_frame)
    @named abs_v_sensor = AbsoluteVelocity(; resolve_in_frame)
    @named rel_pos_sensor1 = RelativePosition(; resolve_in_frame)
    @named rel_pos_sensor2 = RelativePosition(; resolve_in_frame)

    connections = [
        connect(body1.frame, abs_pos_sensor.frame_a),
        connect(rel_pos_sensor1.frame_a, body1.frame),
        connect(rel_pos_sensor1.frame_b, base.frame),
        connect(rel_pos_sensor2.frame_b, body1.frame),
        connect(rel_pos_sensor2.frame_a, body2.frame),
        connect(body1.frame, abs_v_sensor.frame_a),
        [s ~ 0 for s in (body1.phi, body2.phi, body1.fx, body1.fy, body2.fx, body2.fy)]...,
    ]

    @named model = ODESystem(connections,
        t,
        [],
        [],
        systems = [
            body1,
            body2,
            base,
            abs_pos_sensor,
            abs_v_sensor,
            rel_pos_sensor1,
            rel_pos_sensor2,
        ])

    sys = structural_simplify(model)
    unset_vars = setdiff(states(sys), keys(ModelingToolkit.defaults(sys)))
    prob = ODEProblem(sys, unset_vars .=> 0.0, tspan, []; jac = true)

    sol = solve(prob, Rodas5P())
    @test SciMLBase.successful_retcode(sol)

    # the two bodyies falled the same distance, and so the absolute sensor attached to body1
    @test sol[abs_pos_sensor.y.u][end] ≈ sol[body1.ry][end] ≈ sol[body2.ry][end] ≈
          0.5 * g * tspan[end]^2

    # sensor1 is attached to body1, so the relative y-position between body1 and the base is
    # equal to the y-position of body1
    @test sol[body1.ry][end] ≈ -sol[rel_pos_sensor1.rel_y.u][end]

    # the relative y-position between body1 and body2 is zero
    @test sol[rel_pos_sensor2.rel_y.u][end] == 0

    # no displacement in the x-direction
    @test sol[abs_pos_sensor.x.u][end] ≈ sol[body1.rx][end] ≈ sol[body2.rx][end]

    # velocity after t seconds v = g * t
    @test sol[abs_v_sensor.v_y.u][end] ≈ g * tspan[end]
end

@testset "Measure Demo" begin
    @test_nowarn @named abs_v_w = AbsoluteVelocity(; resolve_in_frame = :world)
    @test_nowarn @named abs_v_fa = AbsoluteVelocity(; resolve_in_frame = :frame_a)
    @test_nowarn @named abs_v_fr = AbsoluteVelocity(; resolve_in_frame = :frame_resolve)
end
