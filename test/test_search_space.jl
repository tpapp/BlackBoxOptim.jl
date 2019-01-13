@testset "Search space" begin
    @testset "in()" begin
        for i in 1:NumTestRepetitions
            reps = rand(1:10)
            ss1 = RectSearchSpace(reps, (0.0, 1.0))
            ind = rand_individual(ss1)
            for j in 1:reps
                @test (dimmin(ss1, j) <= ind[j] <= dimmax(ss1, j))
            end
        end
    end

    @testset "RectSearchSpace" begin
        @testset "RectSearchSpace() with given ranges per dimension" begin
            ss = RectSearchSpace([(0.0, 1.0)])
            @test dimmin(ss) == [0.0]
            @test dimmax(ss) == [1.0]
            @test dimdelta(ss) == [1.0]

            ss = RectSearchSpace([(0.0, 1.0), (0.5, 10.0)])
            @test dimmin(ss) == [0.0, 0.5]
            @test dimmax(ss) == [1.0, 10.0]
            @test dimdelta(ss) == [1.0, 9.5]
        end

        @testset "RectSearchSpace() search space with the default range" begin
            ss1 = RectSearchSpace(1)
            @test numdims(ss1) == 1
            @test dimmin(ss1) == [0.0]
            @test dimmin(ss1, 1) == 0.0
            @test dimmax(ss1) == [1.0]
            @test dimmax(ss1, 1) == 1.0
            @test dimdelta(ss1) == [1.0]
            @test dimdelta(ss1, 1) == 1.0
            @test dimrange(ss1) == [(0.0, 1.0)]
            @test dimrange(ss1, 1) == (0.0, 1.0)

            for i in 1:NumTestRepetitions
                ind = rand_individual(ss1)
                @test size(ind) == (1,)
                @test in(ind, ss1)
            end

            ss3 = RectSearchSpace(3)
            @test numdims(ss3) == 3
            @test dimmin(ss3) == [0.0, 0.0, 0.0]
            @test dimmin(ss3, 2) == 0.0
            @test dimmax(ss3) == [1.0, 1.0, 1.0]
            @test dimmax(ss3, 2) == 1.0
            @test dimdelta(ss3) == [1.0, 1.0, 1.0]
            @test dimdelta(ss3, 2) == 1.0
            @test dimrange(ss3) == [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)]
            @test dimrange(ss3, 1) == (0.0, 1.0)
            @test dimrange(ss3, 2) == (0.0, 1.0)
            @test dimrange(ss3, 3) == (0.0, 1.0)

            for i in 1:NumTestRepetitions
                ind = rand_individual(ss3)
                @test size(ind) == (3,)
                @test in(ind, ss3)
            end
        end

        @testset "ContinuousRectSearchSpace with given range" begin
            ss1 = RectSearchSpace(1, (-1.0, 1.0))
            @test_throws ArgumentError RectSearchSpace(1, (0.0, -1.0))
            @test ss1 isa ContinuousRectSearchSpace
            @test numdims(ss1) == 1
            @test dimrange(ss1) == [(-1.0, 1.0)]
            @test dimrange(ss1, 1) == (-1.0, 1.0)

            for i in 1:NumTestRepetitions
                dims = rand(1:100)
                a = rand()
                range = (a, a + (1-a)*rand())
                ss = RectSearchSpace(dims, range)
                @test numdims(ss) == dims
                @test all(dr -> dr == range, dimrange(ss))
            end
        end
    end

    @testset "rand_individuals()" begin
        @testset "rand_individual() is within the search space" begin
            for i in 1:NumTestRepetitions
                reps = rand(1:100)
                mm = sort(rand(2,1), dims=1)
                range = (mm[1], mm[2])
                ss = RectSearchSpace(reps, range)
                ind = rand_individual(ss)
                @test length(ind) == numdims(ss)
                @test in(ind, ss)
            end
        end

        @testset "rand_individuals() creates many individuals and all are within the search space" begin
            for i in 1:NumTestRepetitions
                reps = rand(1:10)
                mm = sort(rand(2,1), dims=1)
                range = (mm[1], mm[2])
                ss = RectSearchSpace(reps, range)
                numinds = rand(1:10)
                inds = rand_individuals(ss, numinds)
                @test size(inds,1) == numdims(ss)
                @test size(inds,2) == numinds
                for j in 1:numinds
                    @test in(inds[:,j], ss)
                end
            end
        end

        @testset "rand_individuals() correctly handles individual dimensions" begin
            for _ in 1:NumTestRepetitions÷10
                numdimensions = rand(1:13)
                minbounds = rand(numdimensions)
                maxbounds = minbounds .+ rand(1:10, numdimensions) .* rand(numdimensions)
                ss = RectSearchSpace(tuple.(minbounds, maxbounds))
                @test dimmin(ss) == minbounds
                @test dimmax(ss) == maxbounds
                @test round.(dimdelta(ss), digits=6) == round.(maxbounds .- minbounds, digits=6)

                # Now generate 100 individuals and make sure they are all within bounds
                inds = rand_individuals(ss, 100)
                @test size(inds, 2) == 100
                @inbounds for i in 1:size(inds, 2)
                    indi = view(inds, :, i)
                    @test indi == BlackBoxOptim.feasible(indi, ss)
                    @test all(minbounds .<= indi .<= maxbounds)
                end
            end
        end

        @testset "rand_individuals_lhs() samples in LHS intervals" begin
            ss = RectSearchSpace([(0.0, 1.0), (2.0, 3.0), (4.0, 5.0)])

            inds = rand_individuals_lhs(ss, 2)
            @test size(inds, 1) == 3
            @test size(inds, 2) == 2

            sorted = sort(inds, dims=2) # Sort per row --> in their ordered intervals
            @test (0.0 <= sorted[1,1] <= 0.5)
            @test (0.5 <= sorted[1,2] <= 1.0)

            @test (2.0 <= sorted[2,1] <= 2.5)
            @test (2.5 <= sorted[2,2] <= 3.0)

            @test (4.0 <= sorted[3,1] <= 4.5)
            @test (4.5 <= sorted[3,2] <= 5.0)
        end
    end

    @testset "feasible(x, ss) projects `x` to the search space `ss`" begin
        ss = RectSearchSpace([(0.0, 1.0), (2.0, 3.0), (4.0, 5.0)])

        @test BlackBoxOptim.feasible([1.1, 2.0, 4.0], ss) == [1.0, 2.0, 4.0]
        @test BlackBoxOptim.feasible([1.1, 3.0, 4.0], ss) == [1.0, 3.0, 4.0]
        @test BlackBoxOptim.feasible([1.1, 2.0, 5.0], ss) == [1.0, 2.0, 5.0]
        @test BlackBoxOptim.feasible([1.1, 3.0, 5.0], ss) == [1.0, 3.0, 5.0]

        @test BlackBoxOptim.feasible([-0.1, 2.0, 4.0], ss) == [0.0, 2.0, 4.0]
        @test BlackBoxOptim.feasible([-0.1, 3.0, 4.0], ss) == [0.0, 3.0, 4.0]
        @test BlackBoxOptim.feasible([-0.1, 2.0, 5.0], ss) == [0.0, 2.0, 5.0]
        @test BlackBoxOptim.feasible([-0.1, 3.0, 5.0], ss) == [0.0, 3.0, 5.0]

        @test BlackBoxOptim.feasible([0.0, 1.9, 4.0], ss) == [0.0, 2.0, 4.0]
        @test BlackBoxOptim.feasible([0.0, 1.9, 4.0], ss) == [0.0, 2.0, 4.0]
        @test BlackBoxOptim.feasible([1.0, 1.9, 5.0], ss) == [1.0, 2.0, 5.0]
        @test BlackBoxOptim.feasible([1.0, 1.9, 5.0], ss) == [1.0, 2.0, 5.0]

        @test BlackBoxOptim.feasible([0.0, 3.3, 4.0], ss) == [0.0, 3.0, 4.0]
        @test BlackBoxOptim.feasible([0.0, 3.2, 4.0], ss) == [0.0, 3.0, 4.0]
        @test BlackBoxOptim.feasible([1.0, 3.1, 5.0], ss) == [1.0, 3.0, 5.0]
        @test BlackBoxOptim.feasible([1.0, 3.9, 5.0], ss) == [1.0, 3.0, 5.0]

        @test BlackBoxOptim.feasible([-0.4, 3.3, 14.5], ss) == [0.0, 3.0, 5.0]
    end

    @testset "dimrange()" begin
        ss = RectSearchSpace([(0.0, 1.0), (2.0, 3.0), (4.0, 5.0)])
        diams = dimdelta(ss)

        @test length(diams) == 3
        @test diams == [1.0, 1.0, 1.0]
    end

    @testset "vcat(ss1, ss2)" begin
        ss1 = RectSearchSpace([(0.0, 1.0), (2.0, 3.0), (4.0, 5.0)])
        ss2 = RectSearchSpace([(6.0, 7.0), (8.0, 9.0)])

        sscat = vcat(ss1, ss2)
        @test numdims(sscat) == 5
        @test dimmin(sscat) == [0.0, 2.0, 4.0, 6.0, 8.0]
        @test dimmax(sscat) == [1.0, 3.0, 5.0, 7.0, 9.0]
        @test dimdelta(sscat) == fill(1.0, 5)
    end
end
